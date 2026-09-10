import 'package:drift/drift.dart';
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

  test('does not switch to an account outside the saved account list', () async {
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
}
