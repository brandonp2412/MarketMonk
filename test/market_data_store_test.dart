import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/legacy_profile_database.dart' as legacy;
import 'package:market_monk/utils.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'test_log_support.dart';

YahooFinanceCandleData _yahooCandle(DateTime date, {double close = 100}) {
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

DateTime _expectedMarketDay() {
  var day = canonicalMarketDay(DateTime.now());
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

void main() {
  setUp(clearAllSyncCache);

  test('legacy profile candles merge globally by canonical symbol and day',
      () async {
    allowMultipleDriftDatabasesForTest();
    final target = Database.connect(NativeDatabase.memory());
    final defaultProfile =
        legacy.LegacyProfileDatabase.connect(NativeDatabase.memory());
    final secondProfile =
        legacy.LegacyProfileDatabase.connect(NativeDatabase.memory());
    addTearDown(target.close);
    addTearDown(defaultProfile.close);
    addTearDown(secondProfile.close);

    await target.candles.insertOne(
      CandlesCompanion.insert(
        symbol: 'MSFT',
        date: DateTime(2026, 1, 2),
        open: const Value(200),
        high: const Value(205),
        low: const Value(198),
        close: const Value(204),
        adjClose: const Value(204),
        volume: const Value(9000),
      ),
    );

    await defaultProfile.candles.insertOne(
      legacy.CandlesCompanion.insert(
        symbol: ' aapl ',
        date: DateTime(2026, 1, 2, 15),
        close: const Value(100),
      ),
    );
    await defaultProfile.candles.insertOne(
      legacy.CandlesCompanion.insert(
        symbol: 'msft',
        date: DateTime(2026, 1, 2, 8),
        close: const Value(199),
      ),
    );
    await secondProfile.candles.insertOne(
      legacy.CandlesCompanion.insert(
        symbol: 'AAPL',
        date: DateTime(2026, 1, 2, 7),
        open: const Value(99),
        high: const Value(103),
        low: const Value(98),
        close: const Value(102),
        adjClose: const Value(102),
        volume: const Value(5000),
      ),
    );

    final result = await mergeLegacyCandles(
      target: target,
      legacyDatabases: [defaultProfile, secondProfile],
    );

    final rows = await (target.candles.select()
          ..orderBy([(row) => OrderingTerm.asc(row.symbol)]))
        .get();

    expect(result.scannedRows, 3);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.symbol), ['AAPL', 'MSFT']);
    expect(rows.first.date, DateTime(2026, 1, 2));
    expect(rows.first.close, 102);
    expect(rows.first.volume, 5000);
    expect(
      rows.last.close,
      204,
      reason: 'a weaker legacy row must not overwrite better global data',
    );

    final secondPass = await mergeLegacyCandles(
      target: target,
      legacyDatabases: [defaultProfile, secondProfile],
    );
    expect(secondPass.writtenRows, 0);
    expect(await target.select(target.candles).get(), hasLength(2));
  });

  test('raw and normalized symbol currency metadata share the global store',
      () async {
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(target.close);

    await upsertSymbolCurrencyMetadata(
      ' azn.l ',
      'GBp',
      database: target,
      cachedAt: DateTime(2026, 10, 3),
    );

    final metadata = await target.readSymbolMetadata('AZN.L');
    expect(metadata == null, isFalse);
    expect(metadata!.currency, 'GBP');
    expect(rawCurrencyFromMetadata(metadata), 'GBp');
  });

  test('IBKR-populated candles satisfy local chart reads from the same cache',
      () async {
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(target.close);
    cacheSymbolMeta('AAPL', 'USD');

    final latest = _expectedMarketDay();
    final requiredFrom = latest.subtract(const Duration(days: 14));
    await insertIbkrCandles(
      [
        IbkrHistoricalCandle(
          date: requiredFrom,
          open: 99,
          high: 101,
          low: 98,
          close: 100,
          volume: 1000,
        ),
        IbkrHistoricalCandle(
          date: latest,
          open: 122,
          high: 124,
          low: 121,
          close: 123,
          volume: 2000,
        ),
      ],
      ' aapl ',
      database: target,
    );

    final prices = await fetchLatestPrices(['AAPL'], database: target);
    expect(prices['AAPL'], 123);

    var localRequests = 0;
    await syncCandles(
      'AAPL',
      database: target,
      syncNamespace: 'Local',
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        localRequests++;
        return const [];
      },
    );
    expect(localRequests, 0);
  });

  test('IBKR candle import removes closed-weekend rows', () async {
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(target.close);

    await target.upsertCandle(
      symbol: 'AVUV',
      date: DateTime(2026, 10, 3),
      open: 100,
      high: 101,
      low: 99,
      close: 100,
      volume: 10,
      adjClose: 100,
    );

    final stored = await insertIbkrCandles(
      [
        IbkrHistoricalCandle(
          date: DateTime(2026, 10, 2),
          open: 101,
          high: 103,
          low: 100,
          close: 102,
          volume: 1000,
        ),
        IbkrHistoricalCandle(
          date: DateTime(2026, 10, 3),
          open: 102,
          high: 104,
          low: 101,
          close: 103,
          volume: 1000,
        ),
      ],
      'AVUV',
      database: target,
    );

    final rows = await target.readCandles('AVUV');
    expect(stored, 1);
    expect(rows, hasLength(1));
    expect(rows.single.date, DateTime(2026, 10, 2));
    expect(rows.single.close, 102);
  });

  test('sync coalescing ignores account namespace for shared market data',
      () async {
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(target.close);
    cacheSymbolMeta('AAPL', 'USD');

    final latest = _expectedMarketDay();
    final requiredFrom = latest.subtract(const Duration(days: 14));
    var requests = 0;

    Future<List<YahooFinanceCandleData>> fetch(
      String symbol,
      DateTime startDate,
    ) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return [
        _yahooCandle(requiredFrom),
        _yahooCandle(latest, close: 105),
      ];
    }

    await Future.wait([
      syncCandles(
        'AAPL',
        database: target,
        syncNamespace: 'Local',
        requiredFrom: requiredFrom,
        yahooFetcher: fetch,
      ),
      syncCandles(
        'AAPL',
        database: target,
        syncNamespace: 'IBKR',
        requiredFrom: requiredFrom,
        yahooFetcher: fetch,
      ),
    ]);

    expect(requests, 1);
    expect(await target.select(target.candles).get(), hasLength(2));
  });
}
