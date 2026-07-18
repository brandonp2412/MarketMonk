import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/utils.dart';
import 'package:test/test.dart';

Trade _trade({
  int id = 1,
  String symbol = 'AZN.L',
  String name = 'AstraZeneca',
  double quantity = 10,
  double price = 3351.0,
  String tradeType = 'open',
}) =>
    Trade(
      id: id,
      symbol: symbol,
      name: name,
      quantity: quantity,
      price: price,
      tradeType: tradeType,
      tradeDate: DateTime(2025, 3, 1),
      realizedPL: 0,
      commission: 0,
    );

void main() {
  group('Issue #30 — UK GBX/GBP scale', () {
    setUp(() {
      allRatesFromUsd['GBP'] = 0.8;
    });

    test('cacheSymbolMeta normalizes cent codes', () {
      expect(cacheSymbolMeta('AZN.L', 'GBp'), 'GBP');
      expect(symbolCurrency('AZN.L'), 'GBP');
      expect(symbolCentDivisor('AZN.L'), 100.0);

      expect(cacheSymbolMeta('LTI.L', 'GBP'), 'GBP');
      expect(symbolCentDivisor('LTI.L'), 1.0);

      expect(cacheSymbolMeta('AGL.JO', 'ZAc'), 'ZAR');
      expect(symbolCentDivisor('AGL.JO'), 100.0);
    });

    test('positions convert pence trades and candles to pounds', () {
      cacheSymbolMeta('AZN.L', 'GBp');

      final positions = computePositions(
        [_trade(price: 3351.0)],
        {'AZN.L': 3400.0},
      );

      final p = positions.single;
      expect(p.nativeCurrency, 'GBP');
      expect(p.avgCost, closeTo(33.51, 0.0001));
      expect(p.currentPrice, closeTo(34.0, 0.0001));
      expect(p.currentValue, closeTo(10 * 34.0 / 0.8, 0.0001));
      expect(p.costBasis, closeTo(10 * 33.51 / 0.8, 0.0001));
      expect(p.unrealizedPL, closeTo(10 * (34.0 - 33.51) / 0.8, 0.0001));
      expect(p.change, closeTo((34.0 - 33.51) / 33.51 * 100, 0.0001));
    });

    test('GBP-listed stocks like LTI are not divided by 100', () {
      cacheSymbolMeta('LTI.L', 'GBP');

      final positions = computePositions(
        [_trade(symbol: 'LTI.L', name: 'Lindsell Train', price: 900.0)],
        {'LTI.L': 950.0},
      );

      final p = positions.single;
      expect(p.avgCost, closeTo(900.0, 0.0001));
      expect(p.currentPrice, closeTo(950.0, 0.0001));
    });

    test('fetchLatestPrices + computePositions end-to-end with pence candles',
        () async {
      cacheSymbolMeta('AZN.L', 'GBp');
      final testDb = Database.connect(NativeDatabase.memory());
      addTearDown(testDb.close);

      await testDb.trades.insertOne(
        TradesCompanion.insert(
          symbol: 'AZN.L',
          name: 'AstraZeneca',
          quantity: 10,
          price: 3351.0,
          tradeType: 'open',
          tradeDate: DateTime(2025, 3, 1),
        ),
      );
      await testDb.candles.insertOne(
        CandlesCompanion.insert(
          symbol: 'AZN.L',
          date: DateTime(2025, 3, 10),
          close: const Value(3400.0),
        ),
      );

      final trades = await testDb.trades.select().get();
      final prices = await fetchLatestPrices(['AZN.L'], database: testDb);
      expect(prices['AZN.L'], closeTo(3400.0, 0.0001));

      final p = computePositions(trades, prices).single;
      expect(p.avgCost, closeTo(33.51, 0.0001));
      expect(p.currentPrice, closeTo(34.0, 0.0001));
    });

    test('symbolPriceUnit labels pence stocks with the cent code', () {
      cacheSymbolMeta('AZN.L', 'GBp');
      cacheSymbolMeta('LTI.L', 'GBP');

      expect(symbolPriceUnit('AZN.L'), 'GBp ');
      expect(symbolPriceUnit('LTI.L'), '£');
    });
  });
}
