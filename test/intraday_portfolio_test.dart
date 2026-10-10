import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/ibkr_api.dart';

void main() {
  final start = DateTime.utc(2026, 10, 9, 13, 30);
  final middle = start.add(const Duration(minutes: 15));
  final end = middle.add(const Duration(minutes: 15));

  test('weights real bars and preserves current NAV including residual cash',
      () {
    final result = buildIntradayPortfolio(
      holdings: [
        IntradayPortfolioHolding(
          quantity: 2,
          pricesUsd: {
            start: 100,
            middle: 110,
            end: 120,
          },
        ),
        IntradayPortfolioHolding(
          quantity: 3,
          pricesUsd: {
            start: 50,
            middle: 40,
            end: 60,
          },
        ),
      ],
      currentValueUsd: 1000,
    );
    expect(result.map((point) => point.date), [start, middle, end]);
    expect(result.map((point) => point.valueUsd), [930, 920, 1000]);
  });

  test('starts with complete prices and carries closed-market holdings forward',
      () {
    final result = buildIntradayPortfolio(
      holdings: [
        IntradayPortfolioHolding(
          quantity: 2,
          pricesUsd: {start: 100, end: 110},
        ),
        IntradayPortfolioHolding(
          quantity: -1,
          pricesUsd: {middle: 50, end: 60},
        ),
      ],
      currentValueUsd: 500,
    );
    expect(result.map((point) => point.date), [middle, end]);
    expect(result.map((point) => point.valueUsd), [490, 500]);
  });

  test('converts cent-denominated quotes and FX before weighting shares', () {
    final holding = IntradayPortfolioHolding.fromSeries(
      IntradaySeries(
        currency: 'GBp',
        source: 'Yahoo',
        candles: [
          for (final entry in {start: 100.0, end: 110.0}.entries)
            IbkrHistoricalCandle(
              date: entry.key,
              open: entry.value,
              high: entry.value,
              low: entry.value,
              close: entry.value,
              volume: 1,
            ),
        ],
      ),
      quantity: 3,
      currencyPerUsd: 0.75,
      centDivisor: 100,
    );
    final result =
        buildIntradayPortfolio(holdings: [holding], currentValueUsd: 10);
    expect(result.first.valueUsd, closeTo(9.6, 1e-10));
    expect(result.last.valueUsd, 10);
  });

  test('does not manufacture timestamps or values without usable prices', () {
    expect(buildIntradayPortfolio(holdings: [], currentValueUsd: 100), isEmpty);
    expect(
      buildIntradayPortfolio(
        holdings: [
          IntradayPortfolioHolding(quantity: 2, pricesUsd: {start: double.nan}),
        ],
        currentValueUsd: 100,
      ),
      isEmpty,
    );
  });
}
