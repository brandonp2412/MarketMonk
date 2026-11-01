import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/database.dart';
import 'package:market_monk/exchange_rate_service.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/utils.dart';
import 'package:test/test.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

Trade _trade(
  int id,
  String symbol,
  double price, {
  String? rawCurrency,
  double? usdRateAtTrade,
  double quantity = 1,
}) =>
    Trade(
      id: id,
      symbol: symbol,
      name: symbol,
      quantity: quantity,
      price: price,
      tradeType: quantity > 0 ? 'open' : 'close',
      tradeDate: DateTime.utc(2025, 3, id),
      realizedPL: 0,
      commission: 0,
      rawCurrency: rawCurrency,
      usdRateAtTrade: usdRateAtTrade,
    );

void main() {
  test('broker executions retain their unit when historical FX is enriched',
      () async {
    final original = _trade(
      1,
      'IBKR-USD',
      150,
      rawCurrency: 'USD',
    );
    final hydrated = await enrichHistoricalTradeRates([original]);
    expect(hydrated.single.rawCurrency, 'USD');
    expect(hydrated.single.usdRateAtTrade, 1);
    expect(hydrated.single.price, 150);
  });

  test('GBp to GBP retains the historical pence purchase value', () {
    cacheSymbolMeta('TEST-GBX.L', 'GBP');
    allRatesFromUsd['GBP'] = 0.8;
    final position = computePositions(
      [
        _trade(
          1,
          'TEST-GBX.L',
          3351,
          rawCurrency: 'GBp',
          usdRateAtTrade: 0.8,
          quantity: 10,
        ),
      ],
      {'TEST-GBX.L': 34},
    ).single;
    expect(position.avgCost, closeTo(33.51, 0.0001));
    expect(position.currentPrice, 34);
    expect(position.costBasis, closeTo(418.875, 0.0001));
    expect(position.unrealizedPL, closeTo(6.125, 0.0001));
  });

  test('USD to EUR preserves USD cost and current EUR valuation', () {
    cacheSymbolMeta('TEST-EUR', 'EUR');
    allRatesFromUsd['EUR'] = 0.9;
    final position = computePositions(
      [_trade(1, 'TEST-EUR', 100, rawCurrency: 'USD', usdRateAtTrade: 1)],
      {'TEST-EUR': 95},
    ).single;
    expect(position.costBasis, 100);
    expect(position.currentValue, closeTo(95 / 0.9, 0.0001));
    expect(position.unrealizedPL, closeTo(95 / 0.9 - 100, 0.0001));
  });

  test('mixed quote currencies and transaction-time FX affect cost basis', () {
    cacheSymbolMeta('TEST-MIX', 'GBP');
    allRatesFromUsd['GBP'] = 0.7;
    final position = computePositions(
      [
        _trade(1, 'TEST-MIX', 100, rawCurrency: 'USD', usdRateAtTrade: 1),
        _trade(2, 'TEST-MIX', 70, rawCurrency: 'GBP', usdRateAtTrade: 0.8),
      ],
      {'TEST-MIX': 84},
    ).single;
    expect(position.costBasis, closeTo(187.5, 0.0001));
    expect(position.currentValue, closeTo(240, 0.0001));
    expect(position.unrealizedPL, closeTo(52.5, 0.0001));
  });

  test('quote transitions are stored without changing historical numbers',
      () async {
    final db = Database.connect(NativeDatabase.memory());
    addTearDown(db.close);
    final timestamp = DateTime.utc(2026, 11, 1);
    await db.upsertSymbolMetadata(
      symbol: 'TEST-CHANGE',
      currency: 'GBP',
      payloadJson: '{"rawCurrency":"GBp"}',
      cachedAt: timestamp.subtract(const Duration(days: 2)),
    );
    await db.upsertCandle(
      symbol: 'TEST-CHANGE',
      date: DateTime(2025, 3, 1),
      open: 3351,
      high: 3351,
      low: 3351,
      close: 3351,
      volume: 10,
      adjClose: 3351,
    );
    final changed = await upsertSymbolCurrencyMetadata(
      'TEST-CHANGE',
      'GBP',
      database: db,
      cachedAt: timestamp,
    );
    expect(changed, isTrue);
    final records = await db.readQuoteCurrencyChanges('TEST-CHANGE');
    expect(records, hasLength(1));
    expect(records.single.previousRawCurrency, 'GBp');
    expect(records.single.nextRawCurrency, 'GBP');
    expect(records.single.effectiveDate, isNull);
    cacheSymbolMeta('TEST-CHANGE', 'GBP');
    allRatesFromUsd['GBP'] = 0.8;
    await syncCandles(
      'TEST-CHANGE',
      database: db,
      requiredFrom: DateTime.utc(2025, 3, 1),
      forceRefresh: true,
      yahooFetcher: (_, __) async => [
        YahooFinanceCandleData(
          date: DateTime(2025, 3, 1),
          open: 33.51,
          high: 33.51,
          low: 33.51,
          close: 33.51,
          adjClose: 33.51,
          volume: 10,
        ),
      ],
    );
    // Do not relabel pre-transition provider prices or overwrite the original
    // historical numbers merely because today's quote unit is GBP.
    final candles = await db.readCandles('TEST-CHANGE');
    expect(candles.single.close, 3351);
    expect(candles.single.rawCurrency, isNull);
    expect(
      await upsertSymbolCurrencyMetadata(
        'TEST-CHANGE',
        'GBP',
        database: db,
        cachedAt: timestamp,
      ),
      isFalse,
    );
    expect(await db.readQuoteCurrencyChanges('TEST-CHANGE'), hasLength(1));
  });

  test('historical FX uses the dated pair and verifies its source date',
      () async {
    final quote = await fetchHistoricalUsdRate(
      'GBP',
      DateTime.utc(2025, 3, 2),
      fetcher: (uri) async {
        expect(uri.path, '/v2/rate/USD/GBP');
        expect(uri.queryParameters['date'], '2025-03-02');
        return http.Response(
          '{"date":"2025-02-28","base":"USD","quote":"GBP","rate":0.8}',
          200,
        );
      },
    );
    expect(quote.rate, 0.8);
    expect(quote.rateDate, DateTime.utc(2025, 2, 28));
    await expectLater(
      fetchHistoricalUsdRate(
        'GBP',
        DateTime.utc(2025, 3, 2),
        fetcher: (_) async => http.Response(
          '{"date":"2025-03-03","base":"USD","quote":"GBP","rate":0.8}',
          200,
        ),
      ),
      throwsFormatException,
    );
  });
}
