import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/unified_database.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

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

  test('rename and delete preserve stable profile identity without swapping db',
      () async {
    await seedTestSqlite({
      'accounts': ['Default'],
      'activeAccount': 'Default',
    });
    final manager = testAccountManager();
    await manager.init();
    final runtimeDatabase = db;

    await manager.addAccount('Brokerage');
    await manager.switchAccount('Brokerage');
    final profileId = manager.activeProfileId;

    await manager.renameAccount('Brokerage', 'Long Term');
    expect(manager.activeAccount, 'Long Term');
    expect(manager.activeProfileId, profileId);
    expect(identical(db, runtimeDatabase), isTrue);

    await manager.deleteAccount('Long Term');
    expect(manager.accounts, ['Default']);
    expect(manager.activeAccount, 'Default');
    expect(identical(db, runtimeDatabase), isTrue);
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

      final unifiedDatabase = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(unifiedDatabase.close);
      final manager = AccountManager(unifiedDatabase: unifiedDatabase);
      await manager.init();
      var notifications = 0;
      manager.addListener(() => notifications++);

      final runtimeDatabase = db;
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
      expect(identical(db, runtimeDatabase), isTrue);
    } finally {
      await db.close();
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('importDatabase refreshes active profile state without swapping db',
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
    final sourceDb = Database.connect(
      DatabaseConnection(
        NativeDatabase(sourceFile),
        closeStreamsSynchronously: true,
      ),
    );
    await sourceDb.trades.insertOne(
      TradesCompanion.insert(
        symbol: 'VTI',
        name: 'Vanguard Total Stock Market ETF',
        quantity: 12,
        price: 321.45,
        tradeType: 'open',
        tradeDate: DateTime(2026, 9, 22),
      ),
    );
    await sourceDb.close();

    final unifiedDatabase = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(unifiedDatabase.close);
    final manager = AccountManager(unifiedDatabase: unifiedDatabase);
    await manager.init();
    var notifications = 0;
    manager.addListener(() => notifications++);

    await manager.importDatabase(sourceFile);

    final importedDb = Database.connect(
      DatabaseConnection(
        NativeDatabase(File('${tempDir.path}/market-monk.sqlite')),
        closeStreamsSynchronously: true,
      ),
    );
    final importedTrades = await importedDb.select(importedDb.trades).get();
    expect(importedTrades, hasLength(1));
    expect(importedTrades.single.symbol, 'VTI');
    expect(importedTrades.single.quantity, 12);
    await importedDb.close();
    expect(notifications, 1);
    expect(
      File('${tempDir.path}/market-monk.sqlite').existsSync(),
      isTrue,
    );
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
      final profileDb = Database.connect(
        DatabaseConnection(
          NativeDatabase(File('${tempDir.path}/$fileName')),
          closeStreamsSynchronously: true,
        ),
      );
      await profileDb.trades.insertOne(
        TradesCompanion.insert(
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

    final unifiedDatabase = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(unifiedDatabase.close);
    final manager = AccountManager(unifiedDatabase: unifiedDatabase);
    await manager.init();
    final exportDirectory = await tempDir.createTemp('export-');
    final backup = await manager.exportBackup(exportDirectory);

    expect(backup.path, endsWith('.zip'));
    expect(await backup.exists(), isTrue);

    await manager.switchAccount('Default');
    await manager.deleteAccount('Brokerage');
    final mutatedDefaultDb = Database.connect(
      DatabaseConnection(
        NativeDatabase(File('${tempDir.path}/market-monk.sqlite')),
        closeStreamsSynchronously: true,
      ),
    );
    await mutatedDefaultDb.trades.insertOne(
      TradesCompanion.insert(
        symbol: 'BND',
        name: 'BND',
        quantity: 30,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026, 10, 2),
      ),
    );
    await mutatedDefaultDb.close();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setString('displayCurrency', 'USD');

    await manager.importBackup(backup);

    expect(manager.accounts, ['Default', 'Brokerage']);
    expect(manager.activeAccount, 'Brokerage');
    expect(prefs.getString('displayCurrency'), 'NZD');

    final brokerageDb = Database.connect(
      DatabaseConnection(
        NativeDatabase(File('${tempDir.path}/market-monk-Brokerage.sqlite')),
        closeStreamsSynchronously: true,
      ),
    );
    final brokerageTrades = await brokerageDb.select(brokerageDb.trades).get();
    expect(brokerageTrades, hasLength(1));
    expect(brokerageTrades.single.symbol, 'VXUS');
    expect(brokerageTrades.single.quantity, 20);
    await brokerageDb.close();

    final defaultDb = Database.connect(
      DatabaseConnection(
        NativeDatabase(File('${tempDir.path}/market-monk.sqlite')),
        closeStreamsSynchronously: true,
      ),
    );
    final defaultTrades = await defaultDb.select(defaultDb.trades).get();
    expect(defaultTrades, hasLength(1));
    expect(defaultTrades.single.symbol, 'VTI');
    expect(defaultTrades.single.quantity, 10);
    await defaultDb.close();
  });
}
