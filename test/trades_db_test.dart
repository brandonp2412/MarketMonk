import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

void _overrideSqlite3() {
  open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
}

Database _openDb() => Database.connect(NativeDatabase.memory());

/// Inserts a trade row and returns it.
Future<Trade> _insertTrade(
  Database db, {
  String symbol = 'AAPL',
  String name = 'Apple',
  double quantity = 10,
  double price = 150.0,
  String tradeType = 'open',
  DateTime? tradeDate,
  double realizedPL = 0.0,
  double commission = 2.0,
}) =>
    db.trades.insertReturning(
      TradesCompanion.insert(
        symbol: symbol,
        name: name,
        quantity: quantity,
        price: price,
        tradeType: tradeType,
        tradeDate: tradeDate ?? DateTime(2025, 3, 1),
        realizedPL: Value(realizedPL),
        commission: Value(commission),
      ),
    );

void main() {
  setUpAll(_overrideSqlite3);

  // ─── Basic CRUD ────────────────────────────────────────────────────────────
  group('Trades table — basic CRUD', () {
    late Database db;
    setUp(() => db = _openDb());
    tearDown(() => db.close());

    test('insert and retrieve a trade', () async {
      final inserted = await _insertTrade(db);

      expect(inserted.id, isPositive);
      expect(inserted.symbol, 'AAPL');
      expect(inserted.tradeType, 'open');
      expect(inserted.quantity, closeTo(10.0, 0.001));
      expect(inserted.price, closeTo(150.0, 0.001));
    });

    test('defaults: realizedPL and commission have sensible defaults',
        () async {
      final inserted = await db.trades.insertReturning(
        TradesCompanion.insert(
          symbol: 'GOOG',
          name: 'Alphabet',
          quantity: 1,
          price: 200.0,
          tradeType: 'open',
          tradeDate: DateTime(2025, 1, 1),
        ),
      );

      expect(inserted.realizedPL, equals(0.0));
      expect(inserted.commission, equals(0.0));
    });

    test('multiple trades for the same symbol have distinct IDs', () async {
      final a = await _insertTrade(db, quantity: 10, tradeType: 'open');
      final b = await _insertTrade(
        db,
        quantity: -5,
        tradeType: 'close',
        realizedPL: 150.0,
      );

      expect(a.id, isNot(equals(b.id)));
    });

    test('delete removes only the targeted trade', () async {
      final a = await _insertTrade(db);
      await _insertTrade(db, symbol: 'NVDA', name: 'NVIDIA');

      await (db.trades.delete()..where((t) => t.id.equals(a.id))).go();

      final remaining = await db.trades.select().get();
      expect(remaining, hasLength(1));
      expect(remaining.first.symbol, 'NVDA');
    });

    test('update modifies only specified fields', () async {
      final t = await _insertTrade(db, price: 150.0);

      await (db.trades.update()..where((r) => r.id.equals(t.id)))
          .write(const TradesCompanion(price: Value(175.0)));

      final updated = await (db.trades.select()
            ..where((r) => r.id.equals(t.id)))
          .getSingle();

      expect(updated.price, closeTo(175.0, 0.001));
      expect(
        updated.quantity,
        closeTo(10.0, 0.001),
        reason: 'quantity should be unchanged',
      );
    });
  });

  // ─── Querying trade history for a symbol ──────────────────────────────────
  group('Trades table — querying by symbol', () {
    late Database db;

    setUp(() async {
      db = _openDb();
      await _insertTrade(
        db,
        symbol: 'AAPL',
        quantity: 20,
        tradeType: 'open',
        tradeDate: DateTime(2025, 1, 1),
      );
      await _insertTrade(
        db,
        symbol: 'AAPL',
        quantity: -10,
        tradeType: 'close',
        realizedPL: 300.0,
        tradeDate: DateTime(2025, 6, 1),
      );
      await _insertTrade(
        db,
        symbol: 'META',
        quantity: 5,
        tradeType: 'open',
        tradeDate: DateTime(2025, 2, 1),
      );
    });

    tearDown(() => db.close());

    test('filter by symbol returns only that symbol\'s trades', () async {
      final aaplTrades = await (db.trades.select()
            ..where((t) => t.symbol.equals('AAPL')))
          .get();

      expect(aaplTrades, hasLength(2));
      expect(aaplTrades.every((t) => t.symbol == 'AAPL'), isTrue);
    });

    test('ordering by tradeDate descending returns newest first', () async {
      final ordered = await (db.trades.select()
            ..where((t) => t.symbol.equals('AAPL'))
            ..orderBy([(t) => OrderingTerm.desc(t.tradeDate)]))
          .get();

      expect(
        ordered.first.tradeDate.month,
        6,
        reason: 'June trade should be first (newer)',
      );
      expect(ordered.last.tradeDate.month, 1);
    });

    test('total realizedPL across symbol can be summed', () async {
      final aaplTrades = await (db.trades.select()
            ..where((t) => t.symbol.equals('AAPL')))
          .get();

      final totalPL = aaplTrades.fold(0.0, (sum, t) => sum + t.realizedPL);
      expect(totalPL, closeTo(300.0, 0.01));
    });
  });

  // ─── Trades table independence (no FK requirement) ─────────────────────────
  group('Trades table — no FK constraints', () {
    late Database db;
    setUp(() => db = _openDb());
    tearDown(() => db.close());

    test('can insert trade for any symbol without a prior dependency',
        () async {
      final inserted = await _insertTrade(db, symbol: 'CLOSED_POS');
      expect(inserted.symbol, 'CLOSED_POS');

      final all = await db.trades.select().get();
      expect(all, hasLength(1));
    });

    test('can insert multiple trades for the same symbol', () async {
      await _insertTrade(db, symbol: 'AAPL', quantity: 10);
      await _insertTrade(db, symbol: 'AAPL', quantity: -5, tradeType: 'close');

      final trades = await (db.trades.select()
            ..where((t) => t.symbol.equals('AAPL')))
          .get();
      expect(trades, hasLength(2));
    });
  });

  // ─── Realized P/L calculations ─────────────────────────────────────────────
  group('Realized P/L arithmetic', () {
    late Database db;
    setUp(() => db = _openDb());
    tearDown(() => db.close());

    test('negative realizedPL (losing trade) is stored and retrieved',
        () async {
      final t = await _insertTrade(
        db,
        quantity: -10,
        tradeType: 'close',
        realizedPL: -250.0,
      );
      expect(t.realizedPL, closeTo(-250.0, 0.001));
    });

    test('zero realizedPL on open trades stays zero', () async {
      final t = await _insertTrade(db, tradeType: 'open', realizedPL: 0.0);
      expect(t.realizedPL, equals(0.0));
    });

    test('sum of realizedPL across multiple closes is correct', () async {
      await _insertTrade(
        db,
        quantity: -5,
        tradeType: 'close',
        realizedPL: 200.0,
      );
      await _insertTrade(
        db,
        quantity: -3,
        tradeType: 'close',
        realizedPL: -80.0,
      );

      final trades = await db.trades.select().get();
      final total = trades.fold(0.0, (s, t) => s + t.realizedPL);
      expect(total, closeTo(120.0, 0.01));
    });
  });
}
