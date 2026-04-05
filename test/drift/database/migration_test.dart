// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/database.dart';
import 'package:test/test.dart';
import 'generated/schema.dart';

import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // ─── Simple schema-shape migrations (all versions) ────────────────────────
  group('simple database migrations', () {
    // Verifies all version-to-version schema transitions produce the correct
    // final table shape.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            await verifier.schemaAt(fromVersion);
            final db = Database.connect(NativeDatabase.memory());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // ─── v7 → v8: trades table created; existing tickers survive ──────────────
  group('v7 → v8 data integrity', () {
    test('existing tickers are preserved after migration', () async {
      final schema = await verifier.schemaAt(7);

      // Populate the v7 database via the versioned schema
      final oldDb = v7.DatabaseAtV7(schema.newConnection());
      await oldDb.into(oldDb.tickers).insert(
            v7.TickersCompanion.insert(
              symbol: 'AAPL',
              name: 'Apple',
              change: 5.0,
              amount: 10.0,
              price: 150.0,
            ),
          );
      await oldDb.into(oldDb.tickers).insert(
            v7.TickersCompanion.insert(
              symbol: 'GOOG',
              name: 'Alphabet',
              change: 12.0,
              amount: 5.0,
              price: 200.0,
            ),
          );
      await oldDb.close();

      // Run the migration on the real database
      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 8);
      await migratingDb.close();

      // Verify with a v8 view of the same database
      final checkDb = v8.DatabaseAtV8(schema.newConnection());
      final tickers =
          await checkDb.select(checkDb.tickers).get();
      expect(tickers, hasLength(2));

      final aapl = tickers.firstWhere((t) => t.symbol == 'AAPL');
      expect(aapl.amount, closeTo(10.0, 0.001));
      expect(aapl.price, closeTo(150.0, 0.001));
      expect(aapl.change, closeTo(5.0, 0.001));

      await checkDb.close();
    });

    test('trades table is empty after migration (no data loss)', () async {
      final schema = await verifier.schemaAt(7);

      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 8);
      await migratingDb.close();

      final checkDb = v8.DatabaseAtV8(schema.newConnection());
      final trades = await checkDb.select(checkDb.trades).get();
      expect(
        trades,
        isEmpty,
        reason: 'trades table must be created empty; no old data to migrate',
      );
      await checkDb.close();
    });

    test('can insert trades after v7→v8 migration', () async {
      final schema = await verifier.schemaAt(7);

      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 8);
      await migratingDb.close();

      // Open with the app's live database and try a full round-trip
      final appDb = Database.connect(schema.newConnection());
      await appDb.trades.insertOne(
        TradesCompanion.insert(
          symbol: 'NVDA',
          name: 'NVIDIA',
          quantity: 10.0,
          price: 100.0,
          tradeType: 'open',
          tradeDate: DateTime(2025, 1, 10),
        ),
      );

      final stored = await appDb.trades.select().get();
      expect(stored, hasLength(1));
      expect(stored.first.symbol, 'NVDA');
      expect(stored.first.realizedPL, equals(0.0));
      expect(stored.first.commission, equals(0.0));

      await appDb.close();
    });

    test('tickers table still accepts inserts after v7→v8 migration', () async {
      final schema = await verifier.schemaAt(7);

      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 8);
      await migratingDb.close();

      final appDb = Database.connect(schema.newConnection());
      final now = DateTime.now();
      await appDb.tickers.insertOne(
        TickersCompanion.insert(
          symbol: 'TSLA',
          name: 'Tesla',
          change: 8.0,
          amount: 3.0,
          price: 250.0,
          purchasedAt: Value(now),
        ),
      );

      final rows = await appDb.tickers.select().get();
      expect(rows, hasLength(1));
      expect(rows.first.symbol, 'TSLA');

      await appDb.close();
    });
  });
}
