import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('freshly created database matches the declared schema', () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customSelect('SELECT 1').get();
    await database.validateDatabaseSchema();
  });
}
