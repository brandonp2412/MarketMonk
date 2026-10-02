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
import 'package:market_monk/sqlite_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStateDatabase appState;
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
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
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
      'full backup restores SQLite globals, IBKR state and committed WAL trades',
      () async {
    final settings = await start();
    final manager = AccountManager();
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
    final writer = profile('Brokerage');
    await writer.customStatement('PRAGMA journal_mode=WAL');
    await writer.customStatement('PRAGMA wal_autocheckpoint=0');
    await writer.trades.insertOne(
      TradesCompanion.insert(
        symbol: 'VTI',
        name: 'VTI',
        quantity: 2,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026),
      ),
    );
    final exportDirectory = await directory.createTemp('export-');
    final backup = await manager.exportBackup(exportDirectory);
    await writer.close();
    await manager.deleteAccount('Brokerage');
    await settings.remove('favoriteStocks');
    await manager.importBackup(backup);
    expect(settings.getStringList('favoriteStocks'), ['VTI']);
    expect(manager.ibkrConfigFor('Brokerage').token, 'backup-token');
    expect(manager.portfolioCacheFor('Brokerage')!.netLiquidationUsd, 987);
    final restored = profile('Brokerage');
    expect((await restored.select(restored.trades).get()).single.symbol, 'VTI');
    await restored.close();
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
    final source = await directory.createTemp('invalid-');
    final corrupt = File('${source.path}/market-monk.sqlite');
    await corrupt.writeAsBytes(
      [...utf8.encode('SQLite format 3\u0000'), ...List.filled(100, 0)],
    );
    final archive = await buildMarketMonkBackupArchive(
      databaseDirectory: source,
      workingDirectory: source,
      accounts: ['Default'],
      activeAccount: 'Default',
      settings: {'languageCode': 'de'},
    );
    await expectLater(manager.importBackup(archive), throwsA(anything));
    expect(settings.getString('languageCode'), 'fr');
    expect(manager.ibkrConfigFor().token, 'original');
    expect(await appState.readSetting('languageCode'), 'fr');
  });
}
