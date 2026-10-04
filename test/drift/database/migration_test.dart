// dart format width=80
// ignore_for_file: unused_local_variable, unused_import

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/legacy_profile_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;
import 'generated/schema_v12.dart' as v12;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v10 migrates to the profile-scoped IBKR persistence schema', () async {
    final schema = await verifier.schemaAt(10);
    addTearDown(schema.close);

    final database = LegacyProfileDatabase.connect(schema.newConnection());
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

  test('v11 deduplicates candles and enforces one row per symbol/date',
      () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final duplicateDate = DateTime.utc(2026, 10, 1);

    await verifier.testWithDataIntegrity(
      oldVersion: 11,
      newVersion: 12,
      createOld: v11.DatabaseAtV11.new,
      createNew: v12.DatabaseAtV12.new,
      openTestedDatabase: LegacyProfileDatabase.connect,
      createItems: (batch, oldDatabase) {
        batch.insertAll(oldDatabase.candles, [
          v11.CandlesData(
            id: 1,
            symbol: 'VTI',
            date: duplicateDate.millisecondsSinceEpoch ~/ 1000,
            open: 100,
            high: 101,
            low: 99,
            close: 100,
            volume: 10,
            adjClose: 100,
          ),
          v11.CandlesData(
            id: 2,
            symbol: 'VTI',
            date: duplicateDate.millisecondsSinceEpoch ~/ 1000,
            open: 110,
            high: 111,
            low: 109,
            close: 110,
            volume: 20,
            adjClose: 110,
          ),
        ]);
      },
      validateItems: (newDatabase) async {
        final rows = await newDatabase.select(newDatabase.candles).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 2);
        expect(rows.single.close, 110);
      },
    );
  });
}
