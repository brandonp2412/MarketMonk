import 'package:market_monk/database.dart';
import 'package:market_monk/market_data.dart';
import 'package:market_monk/temporal_currency_returns.dart';
import 'package:test/test.dart';

Trade trade(
  int id,
  String symbol,
  double quantity,
  double price,
  int month,
  int day, {
  String currency = 'USD',
  double? historicalRate,
  double commission = 0,
}) =>
    Trade(
      id: id,
      symbol: symbol,
      name: symbol,
      quantity: quantity,
      price: price,
      tradeType: quantity > 0 ? 'open' : 'close',
      tradeDate: DateTime.utc(2026, month, day),
      rawCurrency: currency,
      usdRateAtTrade: historicalRate,
      realizedPL: 0,
      commission: commission,
    );

Position position(
  String symbol,
  double shares,
  double avgUsd,
  double currentUsd,
) =>
    Position(
      symbol: symbol,
      name: symbol,
      nativeCurrency: 'USD',
      netShares: shares,
      avgCost: avgUsd,
      currentPrice: currentUsd,
      firstBuyDate: DateTime.utc(2026, 1, 2),
      lastBuyDate: DateTime.utc(2026, 1, 2),
    );

void main() {
  setUp(() {
    allRatesFromUsd['USD'] = 1;
    allRatesFromUsd['NZD'] = 1.8;
    allRatesFromUsd['EUR'] = 0.88;
  });

  test('NZD purchase basis uses purchase-day USD/NZD rate', () {
    final result = temporalOpenHoldingReturn(
      position: position('FX-USD', 100, 10, 12),
      trades: [trade(1, 'FX-USD', 100, 10, 1, 2)],
      displayCurrency: 'NZD',
      ratesByDate: {DateTime.utc(2026, 1, 2): 1.5},
    )!;
    // Today's valuation: USD 1200 x 1.8 NZD/USD = NZD 2160.
    // Actual paid: USD 1000 x 1.5 NZD/USD = NZD 1500.
    expect(result.gain * 1.8, closeTo(660, 0.0001));
    expect(result.basis * 1.8, closeTo(1500, 0.0001));
    expect(result.percent, closeTo(44, 0.0001));
    expect(position('FX-USD', 100, 10, 12).change, closeTo(20, 0.0001));
  });

  test('partial sales retain the open shares moving-average historical FX', () {
    final result = temporalOpenHoldingReturn(
      position: position('MIX', 15, 15, 24),
      trades: [
        trade(1, 'MIX', 10, 10, 1, 2),
        trade(2, 'MIX', 10, 20, 2, 3),
        trade(3, 'MIX', -5, 25, 3, 4),
      ],
      displayCurrency: 'NZD',
      ratesByDate: {
        DateTime.utc(2026, 1, 2): 1.5,
        DateTime.utc(2026, 2, 3): 1.8,
      },
    )!;
    expect(result.basis * 1.8, closeTo(382.5, 0.0001));
    expect(result.gain * 1.8, closeTo(265.5, 0.0001));
  });

  test('single acquisition date supports split-adjusted broker shares', () {
    final result = temporalOpenHoldingReturn(
      position: position('SPLIT', 30, 10, 13),
      trades: [
        trade(1, 'SPLIT', 10, 50, 1, 2),
        trade(2, 'SPLIT', -20, 60, 2, 3),
      ],
      displayCurrency: 'NZD',
      ratesByDate: {DateTime.utc(2026, 1, 2): 1.4},
    )!;
    expect(result.basis * 1.8, closeTo(420, 0.0001));
    expect(result.gain * 1.8, closeTo(282, 0.0001));
  });

  test('ambiguous share mismatch does not invent FX cost basis', () {
    final result = temporalOpenHoldingReturn(
      position: position('UNKNOWN', 30, 10, 13),
      trades: [
        trade(1, 'UNKNOWN', 10, 50, 1, 2),
        trade(2, 'UNKNOWN', 10, 70, 2, 3),
      ],
      displayCurrency: 'NZD',
      ratesByDate: {
        DateTime.utc(2026, 1, 2): 1.4,
        DateTime.utc(2026, 2, 3): 1.6,
      },
    );
    expect(result, isNull);
  });

  test('missing purchase-day rate is unavailable, never current spot', () {
    final result = temporalOpenHoldingReturn(
      position: position('NOFX', 100, 10, 12),
      trades: [trade(1, 'NOFX', 100, 10, 1, 2)],
      displayCurrency: 'NZD',
      ratesByDate: const {},
    );
    expect(result, isNull);
  });

  test('sales use historical buy and sell rates for realized NZD gain', () {
    final result = temporalRealizedTradeGain(
      trades: [
        trade(1, 'PARTIAL', 10, 10, 1, 2),
        trade(2, 'PARTIAL', -5, 12, 2, 3),
      ],
      displayCurrency: 'NZD',
      ratesByDate: {
        DateTime.utc(2026, 1, 2): 1.5,
        DateTime.utc(2026, 2, 3): 1.7,
      },
    )!;
    expect(result * 1.8, closeTo(27, 0.0001));
  });

  test('realized NZD gain includes historical buy and sell commissions', () {
    final result = temporalRealizedTradeGain(
      trades: [
        trade(1, 'FEE', 10, 10, 1, 2, commission: 2),
        trade(2, 'FEE', -5, 12, 2, 3, commission: 1),
      ],
      displayCurrency: 'NZD',
      ratesByDate: {
        DateTime.utc(2026, 1, 2): 1.5,
        DateTime.utc(2026, 2, 3): 1.7,
      },
    )!;
    // Gross NZD 27 less half the original NZD 3 purchase fee and
    // NZD 1.70 sale fee = NZD 23.80.
    expect(result * 1.8, closeTo(23.8, 0.0001));
  });

  test('same-currency EUR trade preserves original native EUR cost', () {
    cacheSymbolMeta('FX-EUR', 'EUR');
    final etl = trade(
      1,
      'FX-EUR',
      290,
      3.12,
      7,
      6,
      currency: 'EUR',
      historicalRate: 0.85,
    );
    final result = computePositions([etl], {'FX-EUR': 3.12}).single;
    expect(result.avgCost, closeTo(3.12, 0.000001));
    final native = temporalOpenHoldingReturn(
      position: result,
      trades: [etl],
      displayCurrency: 'EUR',
      ratesByDate: {DateTime.utc(2026, 7, 6): 0.85},
    )!;
    expect(native.gain * 0.88, closeTo(0, 0.0001));
  });
}
