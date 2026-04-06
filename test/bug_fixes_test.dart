import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
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
  setUpAll(_overrideSqlite3);

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

      // Edit ONLY the first trade
      await (db.trades.update()..where((t) => t.id.equals(first.id)))
          .write(const TradesCompanion(quantity: Value(99)));

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
}
