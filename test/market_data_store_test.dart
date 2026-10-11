import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/utils.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

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
    final requiredFrom = DateTime(latest.year, latest.month, latest.day - 14);
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

  test('empty Yahoo sync exits after one request when coverage cannot advance',
      () async {
    final target = Database.connect(NativeDatabase.memory());
    addTearDown(target.close);
    cacheSymbolMeta('AAPL', 'USD');

    final latest = _expectedMarketDay();
    final requiredFrom = DateTime(latest.year, latest.month, latest.day - 14);
    var requests = 0;

    await syncCandles(
      'AAPL',
      database: target,
      requiredFrom: requiredFrom,
      yahooFetcher: (symbol, startDate) async {
        requests++;
        return const [];
      },
    );

    expect(requests, 1);
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
