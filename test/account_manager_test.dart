import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_profile_database.dart' as legacy;
import 'package:market_monk/main.dart';
import 'sqlite_test_support.dart';
import 'test_log_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {});

  tearDown(() async {});

  test('repairs a persisted active account that no longer exists', () async {
    await seedTestSqlite({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Removed',
    });

    final manager = testAccountManager();
    await manager.init();

    expect(manager.accounts, ['Default', 'Brokerage']);
    expect(manager.activeAccount, 'Default');
    final prefs = await SqliteSettings.getInstance();
    expect(prefs.getString('activeAccount'), 'Default');
  });

  test('does not switch to an account outside the saved account list',
      () async {
    silenceTalkerForTest();
    await seedTestSqlite({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Default',
    });

    final manager = testAccountManager();
    await manager.init();
    await manager.switchAccount('Removed');

    expect(manager.activeAccount, 'Default');
    final prefs = await SqliteSettings.getInstance();
    expect(prefs.getString('activeAccount'), 'Default');
  });

  test(
      'rename and delete preserve stable profile identity without swapping testDatabase',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('market-monk-delete-');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathProviderChannel,
      (_) async => tempDir.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    await seedTestSqlite({
      'accounts': ['Default'],
      'activeAccount': 'Default',
    });
    final manager = testAccountManager();
    await manager.init();
    final runtimeDatabase = testDatabase;

    await manager.addAccount('Brokerage');
    await manager.switchAccount('Brokerage');
    final profileId = manager.activeProfileId;

    await manager.renameAccount('Brokerage', 'Long Term');
    expect(manager.activeAccount, 'Long Term');
    expect(manager.activeProfileId, profileId);
    expect(identical(testDatabase, runtimeDatabase), isTrue);

    await manager.deleteAccount('Long Term');
    expect(manager.accounts, ['Default']);
    expect(manager.activeAccount, 'Default');
    expect(identical(testDatabase, runtimeDatabase), isTrue);
  });

  test('switchAccount publishes and persists without swapping runtime database',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('market-monk-switch-');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });

    try {
      await seedTestSqlite({
        'accounts': ['Default', 'Brokerage'],
        'activeAccount': 'Default',
      });

      final unifiedDatabase = Database.connect(NativeDatabase.memory());
      addTearDown(unifiedDatabase.close);
      final manager = AccountManager(database: unifiedDatabase);
      await manager.init();
      var notifications = 0;
      manager.addListener(() => notifications++);

      final runtimeDatabase = testDatabase;
      final switchFuture = manager.switchAccount('Brokerage');

      expect(manager.activeAccount, 'Brokerage');
      expect(notifications, 1);

      await switchFuture;
      final prefs = await SqliteSettings.getInstance();
      expect(prefs.getString('activeAccount'), 'Brokerage');
      expect(
        await unifiedDatabase.readActiveProfileId(),
        manager.activeProfileId,
      );
      expect(identical(testDatabase, runtimeDatabase), isTrue);
    } finally {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
      'importDatabase refreshes active profile state without swapping testDatabase',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('market-monk-import-');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await seedTestSqlite({
      'accounts': ['Default'],
      'activeAccount': 'Default',
    });

    final sourceFile = File('${tempDir.path}/import.sqlite');
    final sourceDb = legacy.LegacyProfileDatabase.connect(
      DatabaseConnection(
        NativeDatabase(sourceFile),
        closeStreamsSynchronously: true,
      ),
    );
    await sourceDb.trades.insertOne(
      legacy.TradesCompanion.insert(
        symbol: 'VTI',
        name: 'Vanguard Total Stock Market ETF',
        quantity: 12,
        price: 321.45,
        tradeType: 'open',
        tradeDate: DateTime(2026, 9, 22),
      ),
    );
    await sourceDb.candles.insertOne(
      legacy.CandlesCompanion.insert(
        symbol: 'VTI',
        date: DateTime.utc(2026, 10, 1),
        close: const Value(325.0),
      ),
    );
    await sourceDb.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://ibkr.example',
      token: 'restored-token',
    );
    await sourceDb.close();

    final unifiedDatabase = Database.connect(NativeDatabase.memory());
    addTearDown(unifiedDatabase.close);
    final manager = AccountManager(database: unifiedDatabase);
    await manager.init();
    var notifications = 0;
    manager.addListener(() => notifications++);

    await manager.importDatabase(sourceFile);

    final importedTrades =
        await unifiedDatabase.readTrades(manager.activeProfileId);
    expect(importedTrades, hasLength(1));
    expect(importedTrades.single.symbol, 'VTI');
    expect(importedTrades.single.quantity, 12);
    expect((await unifiedDatabase.readCandles('VTI')).single.close, 325);
    expect(
      (await unifiedDatabase.readIbkrSettings(manager.activeProfileId))!.token,
      'restored-token',
    );
    expect(notifications, 1);
    expect(File('${tempDir.path}/market-monk.sqlite').existsSync(), isFalse);
  });

  test('full backup restores every profile database and account metadata',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('market-monk-backup-roundtrip-');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> createProfileDatabase(
      String fileName,
      String symbol,
      int quantity,
    ) async {
      final profileDb = legacy.LegacyProfileDatabase.connect(
        DatabaseConnection(
          NativeDatabase(File('${tempDir.path}/$fileName')),
          closeStreamsSynchronously: true,
        ),
      );
      await profileDb.trades.insertOne(
        legacy.TradesCompanion.insert(
          symbol: symbol,
          name: symbol,
          quantity: quantity.toDouble(),
          price: 100,
          tradeType: 'open',
          tradeDate: DateTime(2026, 10, 2),
        ),
      );
      await profileDb.close();
    }

    await createProfileDatabase('market-monk.sqlite', 'VTI', 10);
    await createProfileDatabase('market-monk-Brokerage.sqlite', 'VXUS', 20);
    await seedTestSqlite({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Brokerage',
      'displayCurrency': 'NZD',
    });

    final unifiedDatabase = testDatabase;
    final manager = AccountManager(database: unifiedDatabase);
    await manager.init();
    for (final entry in const [
      ('Default', 'VTI', 10.0),
      ('Brokerage', 'VXUS', 20.0),
    ]) {
      final profile = await unifiedDatabase.readProfileByName(entry.$1);
      await unifiedDatabase.addTrade(
        profileId: profile!.id,
        symbol: entry.$2,
        name: entry.$2,
        quantity: entry.$3,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026, 10, 2),
      );
    }
    await unifiedDatabase.upsertCandle(
      symbol: 'VTI',
      date: DateTime.utc(2026, 10, 3),
      open: 101,
      high: 105,
      low: 99,
      close: 104,
      volume: 100,
      adjClose: 104,
    );
    await unifiedDatabase.upsertSymbolMetadata(
      symbol: 'VTI',
      currency: 'USD',
      cachedAt: DateTime.utc(2026, 10, 3),
    );
    final brokerage = await unifiedDatabase.readProfileByName('Brokerage');
    await unifiedDatabase.writeIbkrSettings(
      profileId: brokerage!.id,
      enabled: true,
      baseUrl: 'https://broker.example',
      token: 'backup-token',
    );
    final exportDirectory = await tempDir.createTemp('export-');
    final backup = await manager.exportBackup(exportDirectory);

    expect(backup.path, endsWith('.zip'));
    expect(await backup.exists(), isTrue);

    final legacyArchive = await buildMarketMonkBackupArchive(
      workingDirectory: await tempDir.createTemp('legacy-archive-'),
      logical: const MarketMonkLogicalBackup(
        profiles: ['Default', 'Brokerage'],
        activeProfile: 'Brokerage',
        settings: {'displayCurrency': 'NZD'},
      ),
      storage: MarketMonkBackupStorage.profileDatabases({
        'Default': File('${tempDir.path}/market-monk.sqlite'),
        'Brokerage': File('${tempDir.path}/market-monk-Brokerage.sqlite'),
      }),
    );

    await manager.switchAccount('Default');
    await manager.deleteAccount('Brokerage');
    await unifiedDatabase.addTrade(
      profileId: manager.activeProfileId,
      symbol: 'BND',
      name: 'BND',
      quantity: 30,
      price: 100,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 2),
    );
    await unifiedDatabase.delete(unifiedDatabase.candles).go();
    await unifiedDatabase.delete(unifiedDatabase.symbolMetadata).go();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setString('displayCurrency', 'USD');

    await manager.importBackup(backup);

    expect(manager.accounts, ['Default', 'Brokerage']);
    expect(manager.activeAccount, 'Brokerage');
    expect(prefs.getString('displayCurrency'), 'NZD');

    final restoredBrokerage =
        await unifiedDatabase.readProfileByName('Brokerage');
    final defaultProfile = await unifiedDatabase.readProfileByName('Default');
    final brokerageTrades =
        await unifiedDatabase.readTrades(restoredBrokerage!.id);
    expect(brokerageTrades, hasLength(1));
    expect(brokerageTrades.single.symbol, 'VXUS');
    expect(brokerageTrades.single.quantity, 20);
    final defaultTrades = await unifiedDatabase.readTrades(defaultProfile!.id);
    expect(defaultTrades, hasLength(1));
    expect(defaultTrades.single.symbol, 'VTI');
    expect(defaultTrades.single.quantity, 10);
    expect((await unifiedDatabase.readCandles('VTI')).single.close, 104);
    expect((await unifiedDatabase.readSymbolMetadata('VTI'))!.currency, 'USD');
    expect(
      (await unifiedDatabase.readIbkrSettings(restoredBrokerage.id))!.token,
      'backup-token',
    );
    expect(
      File('${tempDir.path}/market-monk-Brokerage.sqlite').existsSync(),
      isFalse,
    );
    await manager.importBackup(legacyArchive);
    final oldDefault = await unifiedDatabase.readProfileByName('Default');
    final oldBrokerage = await unifiedDatabase.readProfileByName('Brokerage');
    expect(
      (await unifiedDatabase.readTrades(oldDefault!.id)).single.symbol,
      'VTI',
    );
    expect(
      (await unifiedDatabase.readTrades(oldBrokerage!.id)).single.symbol,
      'VXUS',
    );
    expect((await unifiedDatabase.readActiveProfile()), 'Brokerage');
    expect((await unifiedDatabase.readSetting('displayCurrency')), 'NZD');
  });
}
