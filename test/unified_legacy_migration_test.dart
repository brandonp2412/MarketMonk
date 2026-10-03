import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/unified_database.dart';
import 'package:market_monk/unified_legacy_source.dart';

void main() {
  test(
    'migrates populated Default and IBKR Bot profiles atomically and retry-safe',
    () async {
      final fixture = await _createLegacyFixture();
      addTearDown(fixture.close);

      final snapshot = await readLegacyUnifiedSnapshot(
        appState: fixture.appState,
        openProfileDatabase: (name) async => fixture.profileDatabases[name],
        closeProfileDatabases: false,
      );

      var loadCount = 0;
      final target = UnifiedDatabase.connect(
        NativeDatabase.memory(),
        legacySnapshotLoader: () async {
          loadCount++;
          return snapshot;
        },
      );
      addTearDown(target.close);

      final profiles = await target.readProfiles();
      expect(loadCount, 1);
      expect(
        profiles.map((profile) => profile.name),
        ['Default', 'IBKR Bot'],
      );
      expect(
        profiles.map((profile) => profile.sortOrder),
        [0, 1],
      );

      final defaultId =
          profiles.singleWhere((profile) => profile.name == 'Default').id;
      final botId =
          profiles.singleWhere((profile) => profile.name == 'IBKR Bot').id;
      expect(await target.readActiveProfileId(), botId);
      expect(await target.readSetting('displayCurrency'), 'NZD');
      expect(await target.readSetting('showValues'), isTrue);
      final metadata = await target.readSymbolMetadata('VOD.L');
      expect(metadata?.currency, 'GBP');
      expect(metadata?.payloadJson, contains('GBp'));
      expect(
        await target.readSetting(UnifiedDatabase.legacyMigrationCompleteKey),
        isTrue,
      );

      final defaultTrades = await target.readTrades(defaultId);
      expect(defaultTrades, hasLength(1));
      expect(defaultTrades.single.symbol, 'VTI');
      expect(defaultTrades.single.commission, 1.25);

      final botTrades = await target.readTrades(botId);
      expect(botTrades, hasLength(1));
      expect(botTrades.single.symbol, 'AAPL');
      expect(botTrades.single.realizedPL, 45.5);

      final botSettings = await target.readIbkrSettings(botId);
      expect(botSettings?.enabled, isTrue);
      expect(botSettings?.baseUrl, 'https://ibkr.example.test');
      expect(botSettings?.token, 'ibkr-bot-token');

      final botCache = await target.readIbkrCache(
        botId,
        'portfolio',
        'snapshot',
      );
      expect(botCache?.payloadJson, '{"netLiquidation":12345.67}');
      expect(botCache?.cachedAt.toUtc(), DateTime.utc(2026, 10, 3, 5));

      final candles = await target.readCandles('AAPL');
      expect(candles, hasLength(1));
      expect(candles.single.date.toUtc(), DateTime.utc(2026, 10, 2));
      expect(candles.single.close, 253.1);
      expect(candles.single.volume, 1000);

      await target.migrateLegacySnapshot(snapshot);
      expect(await target.readTrades(defaultId), hasLength(1));
      expect(await target.readTrades(botId), hasLength(1));
      expect(await target.readCandles('AAPL'), hasLength(1));

      expect(
        await fixture.defaultDatabase
            .select(fixture.defaultDatabase.trades)
            .get(),
        hasLength(1),
      );
      expect(
        await fixture.botDatabase.readIbkrProfileSettings(),
        isNotNull,
      );
      expect(
        await fixture.botDatabase.select(fixture.botDatabase.candles).get(),
        hasLength(1),
      );
    },
  );

  test('current single-profile settings migrate without losing trade data',
      () async {
    final appState = AppStateDatabase.connect(NativeDatabase.memory());
    final profile = Database.connect(NativeDatabase.memory());
    addTearDown(appState.close);
    addTearDown(profile.close);

    await appState.replaceProfiles(['Default']);
    await appState.setActiveProfile('Default');
    await appState.writeSetting('displayCurrency', 'NZD');
    await profile.into(profile.trades).insert(
          TradesCompanion.insert(
            symbol: 'VOO',
            name: 'Vanguard S&P 500 ETF',
            quantity: 3,
            price: 590,
            tradeType: 'open',
            tradeDate: DateTime.utc(2026, 9, 30),
            commission: const Value(1.1),
          ),
        );

    final snapshot = await readLegacyUnifiedSnapshot(
      appState: appState,
      openProfileDatabase: (_) async => profile,
      closeProfileDatabases: false,
    );
    final target = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(target.close);
    await target.migrateLegacySnapshot(snapshot);

    final migrated = (await target.readProfiles()).single;
    expect(migrated.name, 'Default');
    expect(await target.readActiveProfileId(), migrated.id);
    expect(await target.readSetting('displayCurrency'), 'NZD');
    final trades = await target.readTrades(migrated.id);
    expect(trades, hasLength(1));
    expect(trades.single.symbol, 'VOO');
    expect(trades.single.commission, 1.1);
  });

  test('profile registry prevents renamed or deleted profile resurrection',
      () async {
    final appState = AppStateDatabase.connect(NativeDatabase.memory());
    final defaultDatabase = Database.connect(NativeDatabase.memory());
    final renamedDatabase = Database.connect(NativeDatabase.memory());
    final staleOldDatabase = Database.connect(NativeDatabase.memory());
    final deletedDatabase = Database.connect(NativeDatabase.memory());
    addTearDown(() async {
      await appState.close();
      await defaultDatabase.close();
      await renamedDatabase.close();
      await staleOldDatabase.close();
      await deletedDatabase.close();
    });

    await appState.replaceProfiles(['Default', 'Renamed']);
    await appState.setActiveProfile('Renamed');
    await renamedDatabase.into(renamedDatabase.trades).insert(
          TradesCompanion.insert(
            symbol: 'KEEP',
            name: 'Keep',
            quantity: 1,
            price: 10,
            tradeType: 'open',
            tradeDate: DateTime.utc(2026, 10, 1),
          ),
        );
    await deletedDatabase.into(deletedDatabase.trades).insert(
          TradesCompanion.insert(
            symbol: 'GHOST',
            name: 'Deleted',
            quantity: 1,
            price: 99,
            tradeType: 'open',
            tradeDate: DateTime.utc(2026, 9, 1),
          ),
        );

    final databases = <String, Database>{
      'Default': defaultDatabase,
      'Renamed': renamedDatabase,
      'Old Name': staleOldDatabase,
      'Deleted': deletedDatabase,
    };
    final opened = <String>[];
    final snapshot = await readLegacyUnifiedSnapshot(
      appState: appState,
      openProfileDatabase: (name) async {
        opened.add(name);
        return databases[name];
      },
      closeProfileDatabases: false,
    );

    expect(opened, ['Default', 'Renamed']);
    expect(
      snapshot.profiles.map((profile) => profile.name),
      ['Default', 'Renamed'],
    );

    final target = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(target.close);
    await target.migrateLegacySnapshot(snapshot);

    expect(
      (await target.readProfiles()).map((profile) => profile.name),
      ['Default', 'Renamed'],
    );
    expect(await target.readProfileByName('Old Name'), isNull);
    expect(await target.readProfileByName('Deleted'), isNull);
    final renamed = await target.readProfileByName('Renamed');
    expect(renamed, isNotNull);
    expect((await target.readTrades(renamed!.id)).single.symbol, 'KEEP');
  });

  test('failed migration rolls back and a corrected snapshot can recover',
      () async {
    final target = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(target.close);

    await target.upsertProfile(
      id: 'incomplete-existing',
      name: 'Existing',
      sortOrder: 0,
    );
    await target.setActiveProfileId('incomplete-existing');
    await target.writeSetting('existingSetting', 'keep-me-on-rollback');

    final badSnapshot = LegacyUnifiedSnapshot(
      settings: {
        'displayCurrency': 'NZD',
        'unsupported': DateTime.utc(2026, 10, 3),
      },
      profiles: const [LegacyProfileSnapshot(name: 'Default')],
      activeProfileName: 'Default',
    );

    await expectLater(
      target.migrateLegacySnapshot(badSnapshot),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      (await target.readProfiles()).single.name,
      'Existing',
    );
    expect(await target.readActiveProfileId(), 'incomplete-existing');
    expect(
      await target.readSetting('existingSetting'),
      'keep-me-on-rollback',
    );
    expect(
      await target.readSetting(UnifiedDatabase.legacyMigrationCompleteKey),
      isNull,
    );

    const recoveredSnapshot = LegacyUnifiedSnapshot(
      settings: {'displayCurrency': 'USD'},
      profiles: [LegacyProfileSnapshot(name: 'Default')],
      activeProfileName: 'Default',
    );
    await target.migrateLegacySnapshot(recoveredSnapshot);

    expect(
      (await target.readProfiles()).single.name,
      'Default',
    );
    expect(await target.readSetting('displayCurrency'), 'USD');
    expect(
      await target.readSetting(UnifiedDatabase.legacyMigrationCompleteKey),
      isTrue,
    );
  });
}

class _LegacyFixture {
  _LegacyFixture({
    required this.appState,
    required this.defaultDatabase,
    required this.botDatabase,
  });

  final AppStateDatabase appState;
  final Database defaultDatabase;
  final Database botDatabase;

  Map<String, Database> get profileDatabases => {
        'Default': defaultDatabase,
        'IBKR Bot': botDatabase,
      };

  Future<void> close() async {
    await Future.wait([
      appState.close(),
      defaultDatabase.close(),
      botDatabase.close(),
    ]);
  }
}

Future<_LegacyFixture> _createLegacyFixture() async {
  final appState = AppStateDatabase.connect(NativeDatabase.memory());
  final defaultDatabase = Database.connect(NativeDatabase.memory());
  final botDatabase = Database.connect(NativeDatabase.memory());

  await appState.replaceProfiles(['Default', 'IBKR Bot']);
  await appState.setActiveProfile('IBKR Bot');
  await appState.writeSetting('displayCurrency', 'NZD');
  await appState.writeSetting('showValues', true);
  await appState.writeSetting('symbolRawCurrency_VOD.L', 'GBp');

  await defaultDatabase.into(defaultDatabase.trades).insert(
        TradesCompanion.insert(
          symbol: 'VTI',
          name: 'Vanguard Total Stock Market ETF',
          quantity: 2,
          price: 310,
          tradeType: 'open',
          tradeDate: DateTime.utc(2026, 9, 1),
          commission: const Value(1.25),
        ),
      );
  await defaultDatabase.into(defaultDatabase.candles).insert(
        CandlesCompanion.insert(
          symbol: ' aapl ',
          date: DateTime.utc(2026, 10, 2, 8),
          open: const Value(-1),
          high: const Value(-1),
          low: const Value(-1),
          close: const Value(250),
          volume: const Value(0),
          adjClose: const Value(-1),
        ),
      );

  await botDatabase.into(botDatabase.trades).insert(
        TradesCompanion.insert(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          quantity: -1,
          price: 255,
          tradeType: 'close',
          tradeDate: DateTime.utc(2026, 10, 2),
          realizedPL: const Value(45.5),
          commission: const Value(0.85),
        ),
      );
  await botDatabase.writeIbkrProfileSettings(
    enabled: true,
    baseUrl: 'https://ibkr.example.test',
    token: 'ibkr-bot-token',
  );
  await botDatabase.writeIbkrCache(
    kind: 'portfolio',
    cacheKey: 'snapshot',
    payloadJson: '{"netLiquidation":12345.67}',
    cachedAt: DateTime.utc(2026, 10, 3, 5),
  );
  await botDatabase.into(botDatabase.candles).insert(
        CandlesCompanion.insert(
          symbol: 'AAPL',
          date: DateTime.utc(2026, 10, 2, 18),
          open: const Value(248.2),
          high: const Value(255.4),
          low: const Value(247.8),
          close: const Value(253.1),
          volume: const Value(1000),
          adjClose: const Value(253.1),
        ),
      );

  return _LegacyFixture(
    appState: appState,
    defaultDatabase: defaultDatabase,
    botDatabase: botDatabase,
  );
}
