import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';

import 'generated/schema.dart';

void main() {
  test('generated v1 schema matches the unified database contract', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);
    addTearDown(schema.close);

    final database = Database.connect(schema.newConnection());
    addTearDown(database.close);

    await database.validateDatabaseSchema();

    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.setActiveProfileId('profile-default');

    expect(await database.readActiveProfileId(), 'profile-default');
  });
}
