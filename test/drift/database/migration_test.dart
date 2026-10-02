// dart format width=80
// ignore_for_file: unused_local_variable, unused_import

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v10 migrates to the profile-scoped IBKR persistence schema', () async {
    final schema = await verifier.schemaAt(10);
    addTearDown(schema.close);

    final database = Database.connect(schema.newConnection());
    await verifier.migrateAndValidate(database, 11);

    expect(await database.readIbkrProfileSettings(), isNull);
    expect(await database.readIbkrCache('portfolio', 'snapshot'), isNull);

    await database.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'secret',
    );
    await database.writeIbkrCache(
      kind: 'portfolio',
      cacheKey: 'snapshot',
      payloadJson: '{}',
      cachedAt: DateTime.utc(2026, 10, 2),
    );

    expect((await database.readIbkrProfileSettings())?.enabled, isTrue);
    expect(
      (await database.readIbkrCache('portfolio', 'snapshot'))?.payloadJson,
      '{}',
    );

    await database.close();
  });
}
