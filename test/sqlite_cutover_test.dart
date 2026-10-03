import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/unified_database.dart';
import 'package:market_monk/unified_legacy_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStateDatabase appState;
  late UnifiedDatabase unifiedData;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Database profile(String name) => Database.connect(
        NativeDatabase(
          File(
            '${directory.path}/${databaseFileNameForAccount(name)}',
          ),
        ),
      );

  Future<SqliteSettings> start() async {
    final loaded =
        SqliteSettings.initialize(appState, profileDatabaseFactory: profile);
    return SqliteSettings.useInstance(loaded);
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('monk-cutover-');
    messenger.setMockMethodCallHandler(channel, (call) async => directory.path);
    appState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk.settings.sqlite'),
      ),
    );
    db = Database();
    unifiedData = UnifiedDatabase.connect(NativeDatabase.memory());
    setProfileDataDatabaseForTesting(unifiedData);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
    setProfileDataDatabaseForTesting(null);
    await unifiedData.close();
    await appState.close();
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
      'startup migrates once; restart ignores stale or unavailable preferences',
      () async {
    SharedPreferences.setMockInitialValues({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Brokerage',
      'languageCode': 'fr',
      'favoriteStocks': ['VTI'],
      'ibkrAccountConfigs': jsonEncode({
        'Brokerage': {
          'enabled': true,
          'baseUrl': 'https://broker.test',
          'token': 'old',
        },
      }),
    });
    final settings = await start();
    final manager = AccountManager();
    await manager.init();
    expect(manager.activeAccount, 'Brokerage');
    expect(manager.ibkrConfigFor().token, 'old');
    expect(settings.getStringList('favoriteStocks'), ['VTI']);

    final legacySnapshot = await readLegacyUnifiedSnapshot(
      appState: appState,
      openProfileDatabase: (name) async => profile(name),
    );
    final unified = UnifiedDatabase.connect(NativeDatabase.memory());
    await unified.migrateLegacySnapshot(legacySnapshot);
    final unifiedBrokerage = await unified.readProfileByName('Brokerage');
    expect(unifiedBrokerage, isNotNull);
    expect(
      (await unified.readIbkrSettings(unifiedBrokerage!.id))!.token,
      'old',
    );
    expect(await unified.readSetting('favoriteStocks'), ['VTI']);
    await unified.close();

    await settings.remove('languageCode');
    await settings.setStringList('favoriteStocks', ['VXUS']);
    await manager.deleteAccount('Brokerage');
    await appState.close();
    appState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk.settings.sqlite'),
      ),
    );
    final restarted = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () =>
          throw StateError('Preferences must not be read again'),
      profileDatabaseFactory: profile,
    );
    await SqliteSettings.useInstance(Future.value(restarted));
    final reloaded = AccountManager();
    await reloaded.init();
    expect(reloaded.accounts, ['Default']);
    expect(restarted.getString('languageCode'), isNull);
    expect(restarted.getStringList('favoriteStocks'), ['VXUS']);
    expect(
      (await SharedPreferences.getInstance()).getString('languageCode'),
      'fr',
    );
    expect(
      File('${directory.path}/market-monk-Brokerage.sqlite').existsSync(),
      isFalse,
    );
  });

  test('completed migration skips legacy readers and only retries cleanup',
      () async {
    await appState.writeSetting(legacyAppStateMigrationCompleteKey, true);
    await appState.writeSetting(sqliteMigrationCompleteKey, true);

    var preferenceReads = 0;
    var appStateReads = 0;
    var cleanups = 0;
    final loaded = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () async {
        preferenceReads += 1;
        throw StateError('SharedPreferences must not initialize');
      },
      readLegacyAppStateValues: () async {
        appStateReads += 1;
        throw StateError('Legacy app-state must not be read');
      },
      profileDatabaseFactory: profile,
    );

    expect(preferenceReads, 0);
    expect(appStateReads, 0);
    expect(cleanups, 0);
    expect(
      await appState.readSetting(legacyAppStateCleanupCompleteKey),
      isNull,
    );

    final unified = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(unified.close);
    await unified.writeSetting(
      UnifiedDatabase.legacyMigrationCompleteKey,
      true,
    );
    await loaded.cleanupLegacyAppStateAfterUnifiedMigration(
      unified,
      cleanupLegacyAppState: () async {
        cleanups += 1;
      },
    );
    expect(cleanups, 1);
    expect(
      await appState.readSetting(legacyAppStateCleanupCompleteKey),
      true,
    );

    await loaded.database.close();
    appState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk.settings.sqlite'),
      ),
    );
    await SqliteSettings.initialize(
      appState,
      readLegacyValues: () =>
          throw StateError('SharedPreferences must not initialize'),
      readLegacyAppStateValues: () =>
          throw StateError('Legacy app-state must not be read'),
      profileDatabaseFactory: profile,
    );
  });

  test('repairs profiles lost when the app-state database was renamed',
      () async {
    final legacyAppState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk-app-state.sqlite'),
      ),
    );
    await legacyAppState.replaceProfiles(['Default', 'IBKR Bot']);
    await legacyAppState.setActiveProfile('IBKR Bot');
    await legacyAppState.writeSetting('theme', 'ThemeMode.light');
    await legacyAppState.close();
    File('${directory.path}/market-monk-app-state.sqlite-wal')
        .writeAsStringSync('stale');
    File('${directory.path}/market-monk-app-state.sqlite-shm')
        .writeAsStringSync('stale');

    await appState.replaceProfiles(['Default']);
    await appState.setActiveProfile('Default');
    await appState.writeSetting(sqliteMigrationCompleteKey, true);
    await appState.writeSetting('theme', 'ThemeMode.dark');

    final botDb = profile('IBKR Bot');
    await botDb.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://bot.test',
      token: 'still-there',
    );
    await botDb.close();

    final repaired = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () =>
          throw StateError('SharedPreferences must not be needed for repair'),
      profileDatabaseFactory: profile,
    );
    await SqliteSettings.useInstance(Future.value(repaired));
    final unified = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(unified.close);
    await unified.writeSetting(
      UnifiedDatabase.legacyMigrationCompleteKey,
      true,
    );
    await repaired.cleanupLegacyAppStateAfterUnifiedMigration(unified);

    expect(await appState.readProfiles(), ['Default', 'IBKR Bot']);
    expect(await appState.readActiveProfile(), 'Default');
    expect(await appState.readSetting('theme'), 'ThemeMode.dark');
    expect(
      await appState.readSetting(legacyAppStateMigrationCompleteKey),
      true,
    );
    expect(
      await appState.readSetting(legacyAppStateCleanupCompleteKey),
      true,
    );
    expect(
      File('${directory.path}/market-monk-app-state.sqlite').existsSync(),
      isFalse,
    );
    expect(
      File('${directory.path}/market-monk-app-state.sqlite-wal').existsSync(),
      isFalse,
    );
    expect(
      File('${directory.path}/market-monk-app-state.sqlite-shm').existsSync(),
      isFalse,
    );

    final manager = AccountManager();
    await manager.init();
    expect(manager.accounts, ['Default', 'IBKR Bot']);
    expect(manager.ibkrConfigFor('IBKR Bot').token, 'still-there');

    await repaired.setProfiles(['Default'], 'Default');
    await appState.close();
    appState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk.settings.sqlite'),
      ),
    );

    final restarted = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () =>
          throw StateError('SharedPreferences must not be read again'),
      readLegacyAppStateValues: () =>
          throw StateError('Legacy app state must not be re-imported'),
      profileDatabaseFactory: profile,
    );
    await SqliteSettings.useInstance(Future.value(restarted));

    expect(await appState.readProfiles(), ['Default']);
  });

  test('old app-state-only install preserves profiles and active account',
      () async {
    final legacyAppState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk-app-state.sqlite'),
      ),
    );
    await legacyAppState.replaceProfiles(['Default', 'IBKR Bot']);
    await legacyAppState.setActiveProfile('IBKR Bot');
    await legacyAppState.writeSetting('theme', 'ThemeMode.light');
    await legacyAppState.close();

    final bot = profile('IBKR Bot');
    await bot.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://bot.test',
      token: 'bot-token',
    );
    await bot.close();

    final loaded = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () async => const {},
      profileDatabaseFactory: profile,
    );
    await SqliteSettings.useInstance(Future.value(loaded));

    expect(await appState.readProfiles(), ['Default', 'IBKR Bot']);
    expect(await appState.readActiveProfile(), 'IBKR Bot');
    expect(await appState.readSetting('theme'), 'ThemeMode.light');
    // Import alone must keep the source until the unified migration is
    // confirmed, so an interrupted cutover remains recoverable.
    expect(
      File('${directory.path}/market-monk-app-state.sqlite').existsSync(),
      isTrue,
    );
    final manager = AccountManager();
    await manager.init();
    expect(manager.ibkrConfigFor('IBKR Bot').token, 'bot-token');

    await unifiedData.writeSetting(
      UnifiedDatabase.legacyMigrationCompleteKey,
      true,
    );
    await loaded.cleanupLegacyAppStateAfterUnifiedMigration(unifiedData);
    expect(
      File('${directory.path}/market-monk-app-state.sqlite').existsSync(),
      isFalse,
    );
  });

  test('stale app-state cannot resurrect renamed or deleted profiles',
      () async {
    final legacyAppState = AppStateDatabase.connect(
      NativeDatabase(
        File('${directory.path}/market-monk-app-state.sqlite'),
      ),
    );
    await legacyAppState.replaceProfiles(['Default', 'Old Name', 'Deleted']);
    await legacyAppState.setActiveProfile('Old Name');
    await legacyAppState.writeSetting('legacyOnlySetting', 'preserve-me');
    await legacyAppState.close();

    await appState.replaceProfiles(['Default', 'Renamed']);
    await appState.setActiveProfile('Renamed');
    await appState.writeSetting(sqliteMigrationCompleteKey, true);
    await appState.writeSetting('theme', 'ThemeMode.dark');

    final renamed = profile('Renamed');
    await renamed.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://renamed.test',
      token: 'renamed-token',
    );
    await renamed.close();

    final loaded = await SqliteSettings.initialize(
      appState,
      readLegacyValues: () =>
          throw StateError('SharedPreferences must not be consulted'),
      profileDatabaseFactory: profile,
    );
    await SqliteSettings.useInstance(Future.value(loaded));

    expect(await appState.readProfiles(), ['Default', 'Renamed']);
    expect(await appState.readActiveProfile(), 'Renamed');
    expect(await appState.readSetting('theme'), 'ThemeMode.dark');
    expect(await appState.readSetting('legacyOnlySetting'), 'preserve-me');
    expect(
      File('${directory.path}/market-monk-Old Name.sqlite').existsSync(),
      isFalse,
    );
    expect(
      File('${directory.path}/market-monk-Deleted.sqlite').existsSync(),
      isFalse,
    );

    final manager = AccountManager();
    await manager.init();
    expect(manager.accounts, ['Default', 'Renamed']);
    expect(manager.ibkrConfigFor('Renamed').token, 'renamed-token');
  });

  test(
      'failed migration retries remaining profiles without replacing committed rows',
      () async {
    final legacy = <String, Object?>{
      'accounts': ['Default', 'Brokerage'],
      'theme': 'ThemeMode.light',
      'ibkrAccountConfigs': jsonEncode({
        'Default': {
          'enabled': true,
          'baseUrl': 'https://broker.test',
          'token': 'old',
        },
        'Brokerage': {
          'enabled': true,
          'baseUrl': 'https://broker.test',
          'token': 'other',
        },
      }),
    };
    await expectLater(
      SqliteSettings.initialize(
        appState,
        readLegacyValues: () async => legacy,
        profileDatabaseFactory: (name) {
          if (name == 'Brokerage')
            throw StateError('simulated interrupted import');
          return profile(name);
        },
      ),
      throwsStateError,
    );
    expect(await appState.readSetting(sqliteMigrationCompleteKey), isNull);
    await appState.writeSetting('theme', 'ThemeMode.dark');
    final first = profile('Default');
    await first.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://new.test',
      token: 'new',
    );
    await first.close();

    await SqliteSettings.initialize(
      appState,
      readLegacyValues: () async => legacy,
      profileDatabaseFactory: profile,
    );
    expect(await appState.readSetting(sqliteMigrationCompleteKey), true);
    expect(await appState.readSetting('theme'), 'ThemeMode.dark');
    final defaultDb = profile('Default');
    final otherDb = profile('Brokerage');
    expect((await defaultDb.readIbkrProfileSettings())!.token, 'new');
    expect((await otherDb.readIbkrProfileSettings())!.token, 'other');
    await defaultDb.close();
    await otherDb.close();
  });

  test(
      'rename and delete preserve SQLite ownership including the app-state profile name',
      () async {
    final settings = await start();
    final manager = AccountManager();
    await manager.init();
    await manager.addAccount('app-state');
    const config = IbkrAccountConfig(
      enabled: true,
      baseUrl: 'https://broker.test',
      token: 'sqlite',
    );
    await manager.setIbkrConfig('app-state', config);
    await manager.cachePortfolio('app-state', [], null, netLiquidationUsd: 123);
    await manager.switchAccount('app-state');
    await manager.renameAccount('app-state', 'Renamed');
    final reloaded = AccountManager();
    await reloaded.init();
    expect(reloaded.activeAccount, 'Renamed');
    expect(reloaded.ibkrConfigFor(), config);
    expect(reloaded.portfolioCacheFor()!.netLiquidationUsd, 123);
    await reloaded.deleteAccount('Renamed');
    await reloaded.cachePortfolio('Renamed', [], null);
    expect(
      File('${directory.path}/market-monk-Renamed.sqlite').existsSync(),
      isFalse,
    );
    expect(await settings.database.readProfiles(), ['Default']);
  });

  test('malformed caches do not block valid credential migration', () async {
    SharedPreferences.setMockInitialValues({
      'portfolioCacheV1': '{broken',
      'ibkrPerformanceCacheV1': jsonEncode({
        'Default': {
          '1Y': {'cachedAt': 42},
        },
      }),
      'ibkrAccountConfigs': jsonEncode({
        'Default': {
          'enabled': true,
          'baseUrl': 'https://broker.test',
          'token': 'valid',
        },
      }),
    });
    await start();
    final manager = AccountManager();
    await manager.init();
    expect(manager.ibkrConfigFor().token, 'valid');
    expect(manager.portfolioCacheFor(), isNull);
    expect(manager.ibkrPerformanceCacheFor('Default', '1Y'), isNull);
    expect(await appState.readSetting(sqliteMigrationCompleteKey), true);
  });

  test('invalid connection JSON leaves the upgrade retryable', () async {
    SharedPreferences.setMockInitialValues({'ibkrAccountConfigs': '{broken'});
    await expectLater(start(), throwsFormatException);
    expect(await appState.readSetting(sqliteMigrationCompleteKey), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('ibkrAccountConfigs'),
      '{broken',
    );
    SharedPreferences.setMockInitialValues({});
    await start();
    expect(await appState.readSetting(sqliteMigrationCompleteKey), true);
  });

  test('configuration changes invalidate persisted caches atomically',
      () async {
    await start();
    final manager = AccountManager();
    await manager.init();
    await manager.cachePortfolio('Default', [], null, netLiquidationUsd: 123);
    await manager.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://changed.test',
        token: 'new',
      ),
    );
    final reloaded = AccountManager();
    await reloaded.init();
    expect(reloaded.portfolioCacheFor(), isNull);
    expect(reloaded.ibkrConfigFor().token, 'new');
  });

  test(
      'full backup restores unified trades/candles plus SQLite globals and IBKR state',
      () async {
    final settings = await start();
    final unified = UnifiedDatabase.connect(NativeDatabase.memory());
    setProfileDataDatabaseForTesting(unified);
    setMarketDataDatabaseForTesting(unified);
    addTearDown(() async {
      setProfileDataDatabaseForTesting(null);
      setMarketDataDatabaseForTesting(null);
      await unified.close();
    });

    final manager = AccountManager(unifiedDatabase: unified);
    await manager.init();
    await manager.addAccount('Brokerage');
    await manager.setIbkrConfig(
      'Brokerage',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://broker.test',
        token: 'backup-token',
      ),
    );
    await manager.cachePortfolio('Brokerage', [], null, netLiquidationUsd: 987);
    await settings.setStringList('favoriteStocks', ['VTI']);

    final brokerageProfile = await unified.readProfileByName('Brokerage');
    expect(brokerageProfile, isNotNull);
    await unified.addTrade(
      profileId: brokerageProfile!.id,
      symbol: 'VTI',
      name: 'VTI',
      quantity: 2,
      price: 100,
      tradeType: 'open',
      tradeDate: DateTime(2026),
    );
    await unified.addTrade(
      profileId: brokerageProfile.id,
      symbol: 'NEW',
      name: 'Unified only',
      quantity: 4,
      price: 25,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 3),
      commission: 0.75,
    );
    await unified.upsertCandle(
      symbol: 'VTI',
      date: DateTime.utc(2026, 1, 2),
      open: 100,
      high: 102,
      low: 99,
      close: 101,
      volume: 1000,
      adjClose: 101,
    );
    await unified.upsertCandle(
      symbol: 'NEW',
      date: DateTime.utc(2026, 10, 3),
      open: 24,
      high: 26,
      low: 23,
      close: 25,
      volume: 123,
      adjClose: 25,
    );

    final originalProfileId = brokerageProfile.id;
    final exportDirectory = await directory.createTemp('export-');
    final backup = await manager.exportBackup(exportDirectory);

    await unified.clearTrades(brokerageProfile.id);
    await unified.delete(unified.unifiedCandles).go();
    await manager.deleteAccount('Brokerage');
    await settings.remove('favoriteStocks');

    await manager.importBackup(backup);

    expect(settings.getStringList('favoriteStocks'), ['VTI']);
    expect(manager.ibkrConfigFor('Brokerage').token, 'backup-token');
    expect(manager.portfolioCacheFor('Brokerage')!.netLiquidationUsd, 987);

    final restoredProfile = await unified.readProfileByName('Brokerage');
    expect(restoredProfile, isNotNull);
    expect(restoredProfile!.id, originalProfileId);
    final restoredUnifiedTrades = await unified.readTrades(restoredProfile.id);
    expect(
      restoredUnifiedTrades.map((trade) => trade.symbol).toSet(),
      {'VTI', 'NEW'},
    );
    expect(
      restoredUnifiedTrades
          .singleWhere((trade) => trade.symbol == 'NEW')
          .commission,
      0.75,
    );
    expect((await unified.readCandles('VTI')).single.close, 101);
    expect((await unified.readCandles('NEW')).single.volume, 123);

    expect(await appState.readSetting(sqliteMigrationCompleteKey), true);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('version-one JSON backup restores directly into SQLite', () async {
    final settings = await start();
    final manager = AccountManager();
    await manager.init();
    final manifest = File('${directory.path}/manifest.json');
    await manifest.writeAsString(
      jsonEncode({
        'format': 'market-monk-backup',
        'version': 1,
        'activeAccount': 'Brokerage',
        'profiles': [
          {'name': 'Default', 'database': null},
          {'name': 'Brokerage', 'database': null},
        ],
        'preferences': {
          'pureBlack': true,
          'ibkrAccountConfigs': jsonEncode({
            'Brokerage': {
              'enabled': true,
              'baseUrl': 'https://old.test',
              'token': 'legacy',
            },
          }),
        },
      }),
    );
    final archive = File('${directory.path}/legacy.zip');
    final encoder = ZipFileEncoder()..create(archive.path);
    await encoder.addFile(manifest, 'manifest.json');
    await encoder.close();
    await manager.importBackup(archive);
    expect(manager.activeAccount, 'Brokerage');
    expect(manager.ibkrConfigFor().token, 'legacy');
    expect(settings.getBool('pureBlack'), true);
    expect(settings.snapshot().containsKey('ibkrAccountConfigs'), isFalse);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('failed restore rolls back global settings and profile data', () async {
    final settings = await start();
    await settings.setString('languageCode', 'fr');
    final manager = AccountManager();
    await manager.init();
    await manager.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://original.test',
        token: 'original',
      ),
    );
    await manager.cachePortfolio(
      'Default',
      [],
      null,
      netLiquidationUsd: 321,
    );
    await db.trades.insertOne(
      TradesCompanion.insert(
        symbol: 'KEEP',
        name: 'Keep',
        quantity: 1,
        price: 42,
        tradeType: 'open',
        tradeDate: DateTime(2026, 10, 3),
      ),
    );
    await db.candles.insertOne(
      CandlesCompanion.insert(
        symbol: 'KEEP',
        date: DateTime(2026, 10, 3),
        close: const Value(43),
      ),
    );
    final source = await directory.createTemp('invalid-');
    final corrupt = File('${source.path}/market-monk.sqlite');
    await corrupt.writeAsBytes(
      [...utf8.encode('SQLite format 3\u0000'), ...List.filled(100, 0)],
    );
    final archive = await buildMarketMonkBackupArchive(
      workingDirectory: source,
      logical: const MarketMonkLogicalBackup(
        profiles: ['Default'],
        activeProfile: 'Default',
        settings: {'languageCode': 'de'},
      ),
      storage: MarketMonkBackupStorage.profileDatabases({
        'Default': corrupt,
      }),
    );
    await expectLater(manager.importBackup(archive), throwsA(anything));
    expect(settings.getString('languageCode'), 'fr');
    expect(manager.ibkrConfigFor().token, 'original');
    expect(manager.portfolioCacheFor()!.netLiquidationUsd, 321);
    expect((await db.select(db.trades).get()).single.symbol, 'KEEP');
    expect((await db.select(db.candles).get()).single.symbol, 'KEEP');
    expect(await appState.readSetting('languageCode'), 'fr');
  });
}
