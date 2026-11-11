import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/ibkr_api.dart';

void main() {
  test('allocation uses a single daily valuation before its timestamp', () {
    final date = DateTime.utc(2026, 11, 11, 20);
    final holding = IntradayPortfolioHolding(
      quantity: 3,
      constantPrice: true,
      pricesUsd: {date.add(const Duration(hours: 1)): 100},
    );
    expect(holding.priceAt(date), 100);
  });

  test('allocation reverses only trades after the selected timestamp', () {
    final date = DateTime.utc(2026, 11, 11, 20);
    final holding = IntradayPortfolioHolding(
      quantity: 8,
      trades: [
        IntradayPortfolioTrade(date, 2, 100),
        IntradayPortfolioTrade(date.add(const Duration(minutes: 1)), 3, 100),
      ],
      pricesUsd: {
        date.add(const Duration(minutes: 1)): 101,
        date.subtract(const Duration(minutes: 1)): 99,
        date: 100,
      },
    );
    expect(holding.quantityAt(date), 5);
    expect(holding.priceAt(date), 100);
    expect(holding.priceAt(date.subtract(const Duration(hours: 1))), isNull);
  });

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

  test('a late daily fund valuation preserves earlier stock observations', () {
    final fund = IntradayPortfolioHolding.fromSeries(
      IntradaySeries(
        currency: 'USD',
        source: 'Yahoo',
        isDaily: true,
        candles: [
          IbkrHistoricalCandle(
            date: end,
            open: 50,
            high: 50,
            low: 50,
            close: 50,
            volume: 0,
          ),
        ],
      ),
      quantity: 3,
      currencyPerUsd: 1,
      centDivisor: 1,
    );
    final result = buildIntradayPortfolio(
      holdings: [
        IntradayPortfolioHolding(
          quantity: 2,
          pricesUsd: {start: 100, middle: 110, end: 120},
        ),
        fund,
      ],
      currentValueUsd: 1000,
    );
    expect(result.map((point) => point.date), [start, middle, end]);
    expect(result.map((point) => point.valueUsd), [960, 980, 1000]);
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

  test('mid-window buy changes shares and cash at the trade timestamp', () {
    final result = buildIntradayPortfolio(
      holdings: [
        IntradayPortfolioHolding(
          quantity: 100,
          trades: [IntradayPortfolioTrade(middle, 99, 50)],
          pricesUsd: {start: 100, middle: 110, end: 120},
        ),
      ],
      currentValueUsd: 10000,
    );
    expect(result.map((point) => point.date), [start, middle, end]);
    // The purchase costs 4,950; it must not be valued before it occurred.
    expect(result.map((point) => point.valueUsd), [3050, 9000, 10000]);
  });

  test('mid-window sale removes shares and adds proceeds', () {
    final result = buildIntradayPortfolio(
      holdings: [
        IntradayPortfolioHolding(
          quantity: 1,
          trades: [IntradayPortfolioTrade(middle, -99, 110)],
          pricesUsd: {start: 100, middle: 110, end: 120},
        ),
      ],
      currentValueUsd: 1000,
    );
    expect(result.map((point) => point.valueUsd), [-10, 990, 1000]);
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
