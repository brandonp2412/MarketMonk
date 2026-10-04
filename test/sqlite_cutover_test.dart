import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_database_source.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/legacy_profile_database.dart' as legacy;
import 'package:market_monk/sqlite_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup imports legacy values once and never rereads them', () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    var preferenceReads = 0;
    var appStateReads = 0;
    final settings = await SqliteSettings.initialize(
      database,
      readLegacyAppStateValues: () async {
        appStateReads++;
        return null;
      },
      readLegacyValues: () async {
        preferenceReads++;
        return {
          'accounts': ['Default', 'Brokerage'],
          'activeAccount': 'Brokerage',
          'languageCode': 'fr',
          'favoriteStocks': ['VTI'],
        };
      },
    );
    await SqliteSettings.useInstance(Future.value(settings));

    expect(preferenceReads, 1);
    expect(appStateReads, 1);
    expect(await database.readProfileNames(), ['Default', 'Brokerage']);
    expect(await database.readActiveProfile(), 'Brokerage');
    expect(settings.getString('languageCode'), 'fr');
    expect(settings.getStringList('favoriteStocks'), ['VTI']);

    await settings.remove('languageCode');
    await settings.setStringList('favoriteStocks', ['VXUS']);

    final restarted = await SqliteSettings.initialize(
      database,
      readLegacyValues: () =>
          throw StateError('legacy preferences must not be read again'),
      readLegacyAppStateValues: () =>
          throw StateError('legacy app state must not be read again'),
    );

    expect(preferenceReads, 1);
    expect(appStateReads, 1);
    expect(restarted.getString('languageCode'), isNull);
    expect(restarted.getStringList('favoriteStocks'), ['VXUS']);
    expect(await database.readActiveProfile(), 'Brokerage');
  });

  test('legacy app-state cleanup waits for completed database migration',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    final settings = await SqliteSettings.initialize(
      database,
      readLegacyAppStateValues: () async => null,
      readLegacyValues: () async => const <String, Object?>{},
    );
    var cleanups = 0;

    await settings.cleanupLegacyAppStateAfterMigration(
      cleanupLegacyAppState: () async {
        cleanups++;
      },
    );
    expect(cleanups, 0);

    await database.writeSetting(Database.legacyMigrationCompleteKey, true);
    await settings.cleanupLegacyAppStateAfterMigration(
      cleanupLegacyAppState: () async {
        cleanups++;
      },
    );
    expect(cleanups, 1);
    expect(
      await database.readSetting(legacyAppStateCleanupCompleteKey),
      isTrue,
    );

    await settings.cleanupLegacyAppStateAfterMigration(
      cleanupLegacyAppState: () async {
        cleanups++;
      },
    );
    expect(cleanups, 1);
  });

  test('legacy profile files migrate into the single database', () async {
    final legacyDefault =
        legacy.LegacyProfileDatabase.connect(NativeDatabase.memory());
    final legacyBrokerage =
        legacy.LegacyProfileDatabase.connect(NativeDatabase.memory());
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(() async {
      await legacyDefault.close();
      await legacyBrokerage.close();
      await target.close();
    });

    await legacyDefault.into(legacyDefault.trades).insert(
          legacy.TradesCompanion.insert(
            symbol: 'VTI',
            name: 'Vanguard Total Stock Market ETF',
            quantity: 2,
            price: 310,
            tradeType: 'open',
            tradeDate: DateTime.utc(2026, 9, 1),
          ),
        );
    await legacyBrokerage.into(legacyBrokerage.trades).insert(
          legacy.TradesCompanion.insert(
            symbol: 'AAPL',
            name: 'Apple Inc.',
            quantity: 1,
            price: 250,
            tradeType: 'open',
            tradeDate: DateTime.utc(2026, 10, 1),
          ),
        );
    await legacyBrokerage.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'broker-token',
    );

    final snapshot = await readLegacyDatabaseSnapshot(
      readSettings: () async => {'displayCurrency': 'NZD'},
      readProfileNames: () async => ['Default', 'Brokerage'],
      readActiveProfile: () async => 'Brokerage',
      openProfileDatabase: (name) async =>
          name == 'Default' ? legacyDefault : legacyBrokerage,
      closeProfileDatabases: false,
    );
    await target.migrateLegacySnapshot(snapshot);

    expect(await target.readProfileNames(), ['Default', 'Brokerage']);
    expect(await target.readActiveProfile(), 'Brokerage');
    expect(await target.readSetting('displayCurrency'), 'NZD');

    final brokerage = await target.readProfileByName('Brokerage');
    expect(brokerage, isNotNull);
    expect((await target.readTrades(brokerage!.id)).single.symbol, 'AAPL');
    expect(
      (await target.readIbkrSettings(brokerage.id))?.token,
      'broker-token',
    );
  });

  test('settings restore replaces logical state inside the same database',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    await seedDatabaseFromLegacyValues(
      values: {
        'accounts': ['Default', 'Old'],
        'activeAccount': 'Old',
        'displayCurrency': 'USD',
        'favoriteStocks': ['OLD'],
      },
      database: database,
    );
    await database.writeSetting(sqliteMigrationCompleteKey, true);
    await database.writeSetting(legacyAppStateMigrationCompleteKey, true);
    final settings = await SqliteSettings.load(database);

    await settings.restore(
      {
        'displayCurrency': 'NZD',
        'favoriteStocks': ['VTI', 'VXUS'],
      },
      ['Default', 'Brokerage'],
      'Brokerage',
    );

    expect(await database.readProfileNames(), ['Default', 'Brokerage']);
    expect(await database.readActiveProfile(), 'Brokerage');
    expect(settings.getString('displayCurrency'), 'NZD');
    expect(settings.getStringList('favoriteStocks'), ['VTI', 'VXUS']);
    expect(await database.readProfileByName('Old'), isNull);
  });
}
