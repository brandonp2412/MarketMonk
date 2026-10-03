import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/unified_database.dart';
import 'package:market_monk/utils.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

YahooFinanceCandleData _candle(DateTime date, {double close = 100}) {
  return YahooFinanceCandleData(
    date: date,
    open: close - 1,
    high: close + 1,
    low: close - 2,
    close: close,
    adjClose: close,
    volume: 1000,
  );
}

DateTime _dayOffset(DateTime day, int offsetDays) =>
    DateTime(day.year, day.month, day.day + offsetDays);

DateTime _expectedMarketDay() {
  var day = canonicalMarketDay(DateTime.now());
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

Future<List<UnifiedCandle>> _rows(UnifiedDatabase database) =>
    (database.unifiedCandles.select()
          ..orderBy([
            (row) => OrderingTerm(
                  expression: row.date,
                  mode: OrderingMode.asc,
                ),
          ]))
        .get();

void main() {
  setUp(() {
    backgroundNetworkCoordinator.resetDiagnostics();
    clearAllSyncCache();
    cacheSymbolMeta('AAPL', 'USD');
  });

  test('empty DB fetches only requested range and canonicalizes identity',
      () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    final requestedStarts = <DateTime>[];
    var requests = 0;

    await syncCandles(
      ' aapl ',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        expect(symbol, 'AAPL');
        requestedStarts.add(startDate);
        return [
          _candle(requiredFrom.add(const Duration(hours: 9)), close: 90),
          _candle(expected, close: 101),
          _candle(expected.add(const Duration(hours: 15)), close: 102),
        ];
      },
    );

    final rows = await _rows(database);
    expect(requests, 1);
    expect(requestedStarts, [canonicalMarketDay(requiredFrom)]);
    expect(
      backgroundNetworkCoordinator.startedCount(RequestCategory.yahooCandles),
      1,
    );
    expect(
      backgroundNetworkCoordinator.completedCount(
        RequestCategory.yahooCandles,
      ),
      1,
    );
    expect(
      backgroundNetworkCoordinator.rowCount(RequestCategory.yahooCandles),
      2,
    );
    expect(
      backgroundNetworkCoordinator.startedCount(RequestCategory.marketCandles),
      1,
    );
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.symbol).toSet(), {'AAPL'});
    expect(
      rows.every(
        (row) =>
            row.date.hour == 0 &&
            row.date.minute == 0 &&
            row.date.second == 0 &&
            row.date.millisecond == 0,
      ),
      isTrue,
    );
    expect(rows.last.close, 102);
  });

  test('warm DB performs no market-data request or writes', () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);

    await insertCandles(
      [_candle(requiredFrom), _candle(expected)],
      'AAPL',
      database: database,
    );
    final before = await _rows(database);
    var requests = 0;

    await syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        return const [];
      },
    );

    final after = await _rows(database);
    expect(requests, 0);
    expect(
      backgroundNetworkCoordinator.startedCount(RequestCategory.yahooCandles),
      0,
    );
    expect(
      backgroundNetworkCoordinator.rowCount(RequestCategory.yahooCandles),
      0,
    );
    expect(after, hasLength(before.length));
    expect(
      after.map((row) => (row.symbol, row.date, row.close)),
      before.map((row) => (row.symbol, row.date, row.close)),
    );
  });

  test('stale DB requests only the incremental overlap', () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    final staleLatest = _dayOffset(expected, -3);
    DateTime? requestedStart;
    var requests = 0;

    await insertCandles(
      [_candle(requiredFrom), _candle(staleLatest, close: 95)],
      'AAPL',
      database: database,
    );

    await syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        requestedStart = startDate;
        return [
          _candle(staleLatest, close: 96),
          _candle(expected, close: 103),
        ];
      },
    );

    final rows = await _rows(database);
    expect(requests, 1);
    expect(
      requestedStart,
      canonicalMarketDay(_dayOffset(staleLatest, -1)),
    );
    expect(rows, hasLength(3));
    expect(rows.last.date, expected);
    expect(rows.last.close, 103);
  });

  test('manual refresh requests newest overlap without growing row count',
      () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    DateTime? requestedStart;
    var requests = 0;

    await insertCandles(
      [_candle(requiredFrom), _candle(expected, close: 100)],
      'AAPL',
      database: database,
    );

    await syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      forceRefresh: true,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        requestedStart = startDate;
        return [_candle(expected.add(const Duration(hours: 12)), close: 104)];
      },
    );

    final rows = await _rows(database);
    expect(requests, 1);
    expect(
      requestedStart,
      canonicalMarketDay(_dayOffset(expected, -1)),
    );
    expect(rows, hasLength(2));
    expect(rows.last.close, 104);
  });

  test('concurrent normal and manual refresh share one market request',
      () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    final gate = Completer<List<YahooFinanceCandleData>>();
    var requests = 0;

    Future<List<YahooFinanceCandleData>> fetch(
      String symbol,
      DateTime startDate,
    ) {
      requests++;
      return gate.future;
    }

    final normal = syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: fetch,
    );
    await Future<void>.delayed(Duration.zero);
    final manual = syncCandles(
      'aapl',
      database: database,
      requiredFrom: requiredFrom,
      forceRefresh: true,
      yahooFetcher: fetch,
    );

    expect(requests, 1);
    gate.complete([
      _candle(requiredFrom, close: 90),
      _candle(expected, close: 101),
    ]);
    await Future.wait([normal, manual]);

    expect(requests, 1);
    expect(await _rows(database), hasLength(2));
  });

  test('empty provider response does not retry indefinitely', () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    var requests = 0;

    await syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        return const <YahooFinanceCandleData>[];
      },
    );

    expect(requests, 1);
    expect(await _rows(database), isEmpty);
    expect(
      backgroundNetworkCoordinator.startedCount(RequestCategory.yahooCandles),
      1,
    );
  });

  test('concurrent empty responses coalesce once and terminate', () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final requiredFrom = _dayOffset(expected, -30);
    final gate = Completer<List<YahooFinanceCandleData>>();
    var requests = 0;

    Future<List<YahooFinanceCandleData>> fetch(
      String symbol,
      DateTime startDate,
    ) {
      requests++;
      return gate.future;
    }

    final first = syncCandles(
      'AAPL',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: fetch,
    );
    await Future<void>.delayed(Duration.zero);
    final second = syncCandles(
      'aapl',
      database: database,
      requiredFrom: requiredFrom,
      yahooFetcher: fetch,
    );

    expect(requests, 1);
    gate.complete(const <YahooFinanceCandleData>[]);
    await Future.wait([first, second]);

    expect(requests, 1);
    expect(await _rows(database), isEmpty);
  });

  test('overlapping ranges serialize and only backfill missing coverage',
      () async {
    final database = UnifiedDatabase.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final expected = _expectedMarketDay();
    final shortStart = _dayOffset(expected, -30);
    final longStart = _dayOffset(expected, -365);
    final firstGate = Completer<void>();
    final starts = <DateTime>[];
    var activeRequests = 0;
    var maxActiveRequests = 0;

    Future<List<YahooFinanceCandleData>> fetch(
      String symbol,
      DateTime startDate,
    ) async {
      starts.add(startDate);
      activeRequests++;
      if (activeRequests > maxActiveRequests) {
        maxActiveRequests = activeRequests;
      }
      try {
        if (starts.length == 1) {
          await firstGate.future;
          return [
            _candle(shortStart, close: 95),
            _candle(expected, close: 101),
          ];
        }
        return [
          _candle(longStart, close: 80),
          _candle(expected, close: 102),
        ];
      } finally {
        activeRequests--;
      }
    }

    final shortSync = syncCandles(
      'AAPL',
      database: database,
      requiredFrom: shortStart,
      yahooFetcher: fetch,
    );
    await Future<void>.delayed(Duration.zero);
    final longSync = syncCandles(
      'AAPL',
      database: database,
      requiredFrom: longStart,
      yahooFetcher: fetch,
    );

    expect(starts, [canonicalMarketDay(shortStart)]);
    firstGate.complete();
    await Future.wait([shortSync, longSync]);

    expect(maxActiveRequests, 1);
    expect(starts, [
      canonicalMarketDay(shortStart),
      canonicalMarketDay(longStart),
    ]);
    final rows = await _rows(database);
    expect(
      rows.map((row) => row.date),
      contains(canonicalMarketDay(longStart)),
    );
    expect(rows.last.close, 102);
  });
}
