import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
    SharedPreferences.setMockInitialValues({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Removed',
    });

    final manager = AccountManager();
    await manager.init();

    expect(manager.accounts, ['Default', 'Brokerage']);
    expect(manager.activeAccount, 'Default');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('activeAccount'), 'Default');
  });

  test('does not switch to an account outside the saved account list',
      () async {
    SharedPreferences.setMockInitialValues({
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Default',
    });

    final manager = AccountManager();
    await manager.init();
    await manager.switchAccount('Removed');

    expect(manager.activeAccount, 'Default');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('activeAccount'), 'Default');
  });

  test('importDatabase replaces the active database and notifies listeners',
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

    SharedPreferences.setMockInitialValues({
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

    final manager = AccountManager();
    await manager.init();
    var notifications = 0;
    manager.addListener(() => notifications++);

    await manager.importDatabase(sourceFile);

    final importedTrades = await db.select(db.trades).get();
    expect(importedTrades, hasLength(1));
    expect(importedTrades.single.symbol, 'VTI');
    expect(importedTrades.single.quantity, 12);
    expect(notifications, 1);
    expect(
      File('${tempDir.path}/market-monk.sqlite').existsSync(),
      isTrue,
    );
  });
}
