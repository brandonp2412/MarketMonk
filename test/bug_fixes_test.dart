import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/utils.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

/// Opens a fresh in-memory database at the current schema version.
Database openDb() => Database.connect(NativeDatabase.memory());

/// On Linux the versioned library name is libsqlite3.so.0 — load it
/// explicitly so tests run without the -dev symlink installed.
void _overrideSqlite3() {
  open.overrideForAll(
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
}

/// Builds a minimal [Ticker] for use in [calculateTotalReturns] tests.
Ticker _ticker({
  required double price,
  required double amount,
  required double change,
}) {
  final now = DateTime.now();
  return Ticker(
    id: 1,
    symbol: 'TEST',
    name: 'Test',
    price: price,
    amount: amount,
    change: change,
    createdAt: now,
    updatedAt: now,
    purchasedAt: now,
  );
}

void main() {
  setUpAll(_overrideSqlite3);

  // ─── Issue #14 ────────────────────────────────────────────────────────────
  //
  // Root cause: when a stock's candle `close` defaults to -1.0 (the Candles
  // table default for missing data), syncCandles computes:
  //   change = safePercentChange(purchasePrice=5, close=-1) = -120%
  //
  // A change < -100 makes the denominator (1 + change/100) negative.
  // For example with change=-120%: denominator = 1 - 1.2 = -0.2
  //
  //   initialPositionValue = currentPositionValue / -0.2
  //                        = -5 * currentPositionValue  (wrong sign!)
  //
  // This flips the sign of that position's contribution to totalInitialValue,
  // which in turn makes dollarReturn and percentReturn wildly wrong — the
  // "negative six figures" the issue reporter saw.
  group('Issue #14 — change<-100 (bad candle data) does not corrupt totals',
      () {
    // THE KEY REGRESSION TEST:
    // On OLD code (no change<-100 guard) this fails because the bad ticker
    // flips the sign of totalInitialValue, corrupting the entire result.
    // On NEW code it is skipped and the healthy ticker's return is correct.
    test('ticker with change<-100 (bad candle default) is excluded from totals',
        () {
      // Healthy stock: 10 shares at current price $125, up 25% from purchase.
      // Expected: dollarReturn = +$250, percentReturn = +25%.
      final healthy = _ticker(price: 125, amount: 10, change: 25);

      // Broken ticker: candle close defaulted to -1.0, so syncCandles stored
      // change = safePercentChange(purchasePrice=5, close=-1) = -120%.
      // This should NOT corrupt the portfolio totals.
      final badCandle = _ticker(price: 5, amount: 1, change: -120);

      final (dollar, percent) = calculateTotalReturns([healthy, badCandle]);

      // OLD code: badCandle causes initialPositionValue = 5 / (1-1.2) = -25,
      // so totalInitialValue = 1000 + (-25) = 975. But totalCurrentValue =
      // 1250 + 5 = 1255. dollarReturn = 280, percentReturn = 28.7% — wrong.
      // Worse: if badCandle amount is large the numbers go into six figures.
      //
      // NEW code: badCandle is skipped. Only healthy contributes.
      // dollarReturn = 1250 - 1000 = 250, percentReturn = 25%.
      expect(dollar, closeTo(250.0, 0.01),
          reason: 'bad-candle ticker must not affect the dollar return');
      expect(percent, closeTo(25.0, 0.01),
          reason: 'bad-candle ticker must not affect the percent return');
    });

    test('large bad-candle position drives result to absurd values on old code',
        () {
      // Demonstrate the "negative six figures" scenario:
      // 10,000 shares with bad candle → change=-120%, price=$100.
      // OLD code: initialPositionValue = 1,000,000 / -0.2 = -5,000,000
      //           dollarReturn = 1,000,000 - (-5,000,000) = +6,000,000  (wrong!)
      // NEW code: bad ticker skipped → (0.0, 0.0).
      final badCandle = _ticker(price: 100, amount: 10000, change: -120);

      final (dollar, percent) = calculateTotalReturns([badCandle]);

      expect(dollar, equals(0.0),
          reason: 'ticker with change<-100 must be skipped entirely');
      expect(percent, equals(0.0));
    });

    test('ticker with price==0 is excluded', () {
      final healthy = _ticker(price: 100, amount: 10, change: 25);
      final zeroPriced = _ticker(price: 0, amount: 1, change: -100);

      final (dollar, percent) = calculateTotalReturns([healthy, zeroPriced]);

      expect(dollar, greaterThan(0));
      expect(percent, greaterThan(0));
    });
  });

  // ─── Issue #16 ────────────────────────────────────────────────────────────
  group('Issue #16 — multiple positions for the same stock symbol', () {
    late Database db;

    setUp(() {
      db = openDb();
    });

    tearDown(() => db.close());

    test('inserting two rows with the same symbol succeeds (no unique error)',
        () async {
      final now = DateTime.now();

      await db.tickers.insertOne(TickersCompanion.insert(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        change: 5.0,
        amount: 10,
        price: 150.0,
        purchasedAt: Value(now),
      ));

      // On the OLD schema this second insert would throw a UNIQUE constraint
      // violation.  On the new schema it must succeed.
      await expectLater(
        db.tickers.insertOne(TickersCompanion.insert(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          change: 2.0,
          amount: 5,
          price: 170.0,
          purchasedAt: Value(now),
        )),
        completes,
        reason: 'should be able to insert a second AAPL position',
      );

      final rows = await db.tickers.select().get();
      expect(rows.length, equals(2),
          reason: 'both positions must be stored separately');
      expect(rows.map((r) => r.symbol).toList(), everyElement('AAPL'));
    });

    test('two positions for the same symbol have different IDs', () async {
      final now = DateTime.now();

      final a = await db.tickers.insertReturning(TickersCompanion.insert(
        symbol: 'TSLA',
        name: 'Tesla',
        change: 10.0,
        amount: 3,
        price: 200.0,
        purchasedAt: Value(now),
      ));

      final b = await db.tickers.insertReturning(TickersCompanion.insert(
        symbol: 'TSLA',
        name: 'Tesla',
        change: -3.0,
        amount: 7,
        price: 220.0,
        purchasedAt: Value(now),
      ));

      expect(a.id, isNot(equals(b.id)));
      expect(a.price, equals(200.0));
      expect(b.price, equals(220.0));
    });

    test('editing one position by ID does not affect the other', () async {
      final now = DateTime.now();

      final first = await db.tickers.insertReturning(TickersCompanion.insert(
        symbol: 'MSFT',
        name: 'Microsoft',
        change: 8.0,
        amount: 2,
        price: 300.0,
        purchasedAt: Value(now),
      ));

      await db.tickers.insertReturning(TickersCompanion.insert(
        symbol: 'MSFT',
        name: 'Microsoft',
        change: 4.0,
        amount: 5,
        price: 310.0,
        purchasedAt: Value(now),
      ));

      // Edit ONLY the first position (as the new tickerId-based save does)
      await (db.tickers.update()..where((t) => t.id.equals(first.id)))
          .write(TickersCompanion(amount: const Value(99)));

      final rows = await db.tickers.select().get();
      expect(rows.length, equals(2));

      final updated = rows.firstWhere((r) => r.id == first.id);
      final untouched = rows.firstWhere((r) => r.id != first.id);

      expect(updated.amount, equals(99));
      expect(untouched.amount, equals(5),
          reason: 'second position must not be affected by the edit');
    });
  });
}
