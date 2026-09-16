import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/utils.dart';
import 'package:test/test.dart';

/// Opens a fresh in-memory database at the current schema version.
Database openDb() => Database.connect(NativeDatabase.memory());

Future<Trade> _insertTrade(
  Database db, {
  String symbol = 'AAPL',
  String name = 'Apple',
  double quantity = 10,
  double price = 150.0,
  String tradeType = 'open',
}) =>
    db.trades.insertReturning(
      TradesCompanion.insert(
        symbol: symbol,
        name: name,
        quantity: quantity,
        price: price,
        tradeType: tradeType,
        tradeDate: DateTime(2025, 3, 1),
      ),
    );

void main() {
  // ─── Issue #16 ────────────────────────────────────────────────────────────
  //
  // Multiple trades for the same symbol must all be stored independently.
  // Each trade has its own row and ID — no UNIQUE constraint on symbol.
  group('Issue #16 — multiple trades for the same stock symbol', () {
    late Database db;

    setUp(() {
      db = openDb();
    });

    tearDown(() => db.close());

    test('inserting two trades with the same symbol succeeds', () async {
      await _insertTrade(db, symbol: 'AAPL', quantity: 10, price: 150.0);

      await expectLater(
        _insertTrade(db, symbol: 'AAPL', quantity: 5, price: 170.0),
        completes,
        reason: 'should be able to insert a second AAPL trade',
      );

      final rows = await db.trades.select().get();
      expect(rows.length, equals(2));
      expect(rows.map((r) => r.symbol).toList(), everyElement('AAPL'));
    });

    test('two trades for the same symbol have different IDs', () async {
      final a = await _insertTrade(db, symbol: 'TSLA', quantity: 3);
      final b = await _insertTrade(db, symbol: 'TSLA', quantity: 7);

      expect(a.id, isNot(equals(b.id)));
      expect(a.quantity, closeTo(3.0, 0.001));
      expect(b.quantity, closeTo(7.0, 0.001));
    });

    test('editing one trade by ID does not affect the other', () async {
      final first = await _insertTrade(db, symbol: 'MSFT', quantity: 2);
      await _insertTrade(db, symbol: 'MSFT', quantity: 5);

      await (db.trades.update()..where((t) => t.id.equals(first.id))).write(
        const TradesCompanion(quantity: Value(99)),
      );

      final rows = await db.trades.select().get();
      expect(rows.length, equals(2));

      final updated = rows.firstWhere((r) => r.id == first.id);
      final untouched = rows.firstWhere((r) => r.id != first.id);

      expect(updated.quantity, closeTo(99.0, 0.001));
      expect(
        untouched.quantity,
        closeTo(5.0, 0.001),
        reason: 'second trade must not be affected by the edit',
      );
    });
  });

  group('Issue #25 — native currency provenance', () {
    Trade trade({
      required String symbol,
      required double price,
    }) =>
        Trade(
          id: 1,
          symbol: symbol,
          name: symbol,
          quantity: 1,
          price: price,
          tradeType: 'open',
          tradeDate: DateTime(2026, 1, 1),
          realizedPL: 0,
          commission: 0,
        );

    setUp(() {
      allRatesFromUsd
        ..clear()
        ..['USD'] = 1.0
        ..['INR'] = 84.0;
    });

    test('INR holding is converted to USD exactly once', () {
      cacheSymbolMeta('RELIANCE.NS', 'INR');
      final position = computePositions(
        [trade(symbol: 'RELIANCE.NS', price: 1370)],
        {'RELIANCE.NS': 1370},
      ).single;

      expect(position.nativeCurrency, 'INR');
      expect(position.currentPrice, 1370);
      expect(position.currentValue, closeTo(1370 / 84, 0.000001));
      expect(position.costBasis, closeTo(1370 / 84, 0.000001));
    });

    test('unknown symbol currency is never silently valued as USD', () {
      final position = computePositions(
        [trade(symbol: 'UNKNOWN.NS', price: 1370)],
        {'UNKNOWN.NS': 1370},
      ).single;

      expect(position.nativeCurrency, 'UNKNOWN');
      expect(() => position.currentValue, throwsA(isA<StateError>()));
    });

    test('missing native FX rate makes valuation unavailable', () {
      cacheSymbolMeta('NOFX.NS', 'INR');
      allRatesFromUsd.remove('INR');
      final position = computePositions(
        [trade(symbol: 'NOFX.NS', price: 1370)],
        {'NOFX.NS': 1370},
      ).single;

      expect(() => position.currentValue, throwsA(isA<StateError>()));
      expect(
        () => fmtNativeCurrency(1370, 'INR'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('average cost after sells', () {
    Trade trade({
      required int id,
      required double quantity,
      required double price,
      required DateTime date,
    }) =>
        Trade(
          id: id,
          symbol: 'AAPL',
          name: 'Apple',
          quantity: quantity,
          price: price,
          tradeType: quantity > 0 ? 'open' : 'close',
          tradeDate: date,
          realizedPL: 0,
          commission: 0,
        );

    test('partial sale does not leave sold shares in average cost', () {
      final position = computePositions(
        [
          trade(id: 1, quantity: 10, price: 100, date: DateTime(2025, 1, 1)),
          trade(id: 2, quantity: -9, price: 120, date: DateTime(2025, 2, 1)),
          trade(id: 3, quantity: 1, price: 200, date: DateTime(2025, 3, 1)),
        ],
        {'AAPL': 210},
      ).single;

      expect(position.netShares, 2);
      expect(position.avgCost, closeTo(150, 0.001));
    });

    test('fully closed position resets cost basis before reopening', () {
      final position = computePositions(
        [
          trade(id: 1, quantity: 10, price: 100, date: DateTime(2025, 1, 1)),
          trade(id: 2, quantity: -10, price: 120, date: DateTime(2025, 2, 1)),
          trade(id: 3, quantity: 2, price: 200, date: DateTime(2025, 3, 1)),
        ],
        {'AAPL': 210},
      ).single;

      expect(position.netShares, 2);
      expect(position.avgCost, closeTo(200, 0.001));
    });
  });
}
