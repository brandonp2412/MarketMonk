// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v1 migrates to v2 without changing prices or trade values', () async {
    final tradeDate = DateTime.utc(2025, 3, 1).millisecondsSinceEpoch ~/ 1000;
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: Database.connect,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.profiles, [
          v1.ProfilesData(
            id: 'default',
            name: 'Default',
            sortOrder: 0,
            createdAt: tradeDate,
          ),
        ]);
        batch.insertAll(oldDb.trades, [
          v1.TradesData(
            id: 5,
            profileId: 'default',
            symbol: 'AZN.L',
            name: 'AstraZeneca',
            quantity: 10,
            price: 3351,
            tradeType: 'open',
            tradeDate: tradeDate,
            realizedPL: 0,
            commission: 1,
          ),
        ]);
        batch.insertAll(oldDb.candles, [
          v1.CandlesData(
            symbol: 'AZN.L',
            date: tradeDate,
            open: 3351,
            high: 3360,
            low: 3340,
            close: 3351,
            volume: 100,
            adjClose: 3351,
          ),
        ]);
      },
      validateItems: (newDb) async {
        final trades = await newDb.select(newDb.trades).get();
        final candles = await newDb.select(newDb.candles).get();
        expect(trades, hasLength(1));
        expect(trades.single.id, 5);
        expect(trades.single.price, 3351);
        expect(trades.single.commission, 1);
        expect(trades.single.rawCurrency, isNull);
        expect(trades.single.usdRateAtTrade, isNull);
        expect(trades.single.brokerConid, isNull);
        expect(candles, hasLength(1));
        expect(candles.single.close, 3351);
        expect(candles.single.rawCurrency, isNull);
        expect(await newDb.select(newDb.quoteCurrencyChanges).get(), isEmpty);
      },
    );
  });

  test('upgrading an empty v1 database validates the v2 schema', () async {
    final schema = await verifier.schemaAt(1);
    addTearDown(schema.close);
    final database = Database.connect(schema.newConnection());
    await verifier.migrateAndValidate(database, 2);
    await database.close();
  });
}
