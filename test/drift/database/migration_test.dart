// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/database.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v8 → v9 data integrity', () {
    test('trades are preserved after v8→v9 migration', () async {
      final schema = await verifier.schemaAt(8);

      // Seed v8 with a ticker and a trade
      final oldDb = v8.DatabaseAtV8(schema.newConnection());
      await oldDb.into(oldDb.tickers).insert(
            v8.TickersCompanion.insert(
              symbol: 'AAPL',
              name: 'Apple',
              change: 5.0,
              amount: 10.0,
              price: 150.0,
            ),
          );
      await oldDb.into(oldDb.trades).insert(
            v8.TradesCompanion.insert(
              symbol: 'AAPL',
              name: 'Apple',
              quantity: 10.0,
              price: 150.0,
              tradeType: 'open',
              tradeDate: DateTime(2025, 3, 1).millisecondsSinceEpoch ~/ 1000,
            ),
          );
      await oldDb.close();

      // Migrate to v9
      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 9);
      await migratingDb.close();

      // Verify trades survived via a v9 view
      final checkDb = v9.DatabaseAtV9(schema.newConnection());
      final trades = await checkDb.select(checkDb.trades).get();
      expect(trades, hasLength(1));
      expect(trades.first.symbol, 'AAPL');
      expect(trades.first.quantity, closeTo(10.0, 0.001));
      await checkDb.close();
    });

    test('candles can be inserted without a tickers FK after v8→v9', () async {
      final schema = await verifier.schemaAt(8);

      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 9);
      await migratingDb.close();

      final checkDb = v9.DatabaseAtV9(schema.newConnection());
      // No ticker row required — the FK is gone in v9
      await checkDb.into(checkDb.candles).insert(
            v9.CandlesCompanion.insert(
              symbol: 'TSLA',
              date: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
            ),
          );
      final candles = await checkDb.select(checkDb.candles).get();
      expect(candles, hasLength(1));
      expect(candles.first.symbol, 'TSLA');
      await checkDb.close();
    });

    test('app DB inserts trades correctly after v8→v9 migration', () async {
      final schema = await verifier.schemaAt(8);

      final migratingDb = Database.connect(schema.newConnection());
      await verifier.migrateAndValidate(migratingDb, 9);
      await migratingDb.close();

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
      await appDb.close();
    });
  });
}
