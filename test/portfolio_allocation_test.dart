import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/portfolio_allocation.dart';
import 'package:market_monk/utils.dart';

Position holding(String symbol, double shares, double price) => Position(
      symbol: symbol,
      name: symbol,
      nativeCurrency: 'USD',
      netShares: shares,
      avgCost: price,
      currentPrice: price,
      firstBuyDate: DateTime(2020),
      lastBuyDate: DateTime(2020),
    );

StoredCandle candle(
  String symbol,
  DateTime date,
  double price, {
  String currency = 'USD',
}) =>
    StoredCandle(
      symbol: symbol,
      date: date,
      close: price,
      open: price,
      high: price,
      low: price,
      adjClose: price,
      volume: 1,
      rawCurrency: currency,
    );

Trade trade(String symbol, double quantity, DateTime date) => Trade(
      id: 1,
      symbol: symbol,
      name: symbol,
      quantity: quantity,
      price: 10,
      tradeDate: date,
      tradeType: quantity > 0 ? 'buy' : 'sell',
      realizedPL: 0,
      commission: 0,
    );

void main() {
  test(
      'cash converts from IBKR base currency and never enters historical allocation',
      () {
    final usd = ibkrCashValueUsd(
      cashBalance: const IbkrAccountValue(value: 250, currency: 'NZD'),
      netLiquidation: const IbkrAccountValue(value: 2000, currency: 'NZD'),
      netLiquidationUsd: 1000,
    );
    expect(usd, 125);
    final now = portfolioAllocationAt(
      positions: [holding('A', 5, 25)],
      trades: const [],
      candles: const {},
      date: null,
      cashValueUsd: usd,
    )!;
    expect(now.map((item) => item.value), [125, 125]);
    expect(now.last.isCash, isTrue);
    final past = portfolioAllocationAt(
      positions: [holding('A', 5, 25)],
      trades: const [],
      candles: {
        'A': [candle('A', DateTime(2026, 6, 1), 25)],
      },
      date: DateTime(2026, 6, 1),
      cashValueUsd: usd,
    )!;
    expect(past, hasLength(1));
    expect(past.single.isCash, isFalse);
    allRatesFromUsd.remove('NZD');
    expect(
      ibkrCashValueUsd(
        cashBalance: const IbkrAccountValue(value: 50, currency: 'NZD'),
        netLiquidation: null,
        netLiquidationUsd: null,
      ),
      isNull,
    );
  });

  final date = DateTime(2026, 6, 1);
  final later = DateTime(2026, 6, 2);

  test('allocation restores sales and excludes purchases after the date', () {
    final result = portfolioAllocationAt(
      positions: [
        holding('A', 10, 20),
        holding('B', 5, 20),
        holding('NEW', 5, 10),
      ],
      trades: [
        trade('A', 5, later),
        trade('SOLD', -4, later),
        trade('NEW', 5, later),
      ],
      candles: {
        'A': [candle('A', date, 10)],
        'B': [candle('B', date, 20)],
        'SOLD': [candle('SOLD', date, 50)],
      },
      date: date,
    )!;
    expect(
      {for (final allocation in result) allocation.symbol: allocation.value},
      {'A': 50, 'B': 100, 'SOLD': 200},
    );
  });

  test('all time uses current positions and prices', () {
    final result = portfolioAllocationAt(
      positions: [holding('A', 10, 20)],
      trades: [trade('SOLD', -4, later)],
      candles: {},
      date: null,
    )!;
    expect(result.single.symbol, 'A');
    expect(result.single.value, 200);
  });

  test('missing or stale prices cannot produce a partial allocation', () {
    for (final prices in [
      <StoredCandle>[],
      [candle('A', DateTime(2026, 5, 20), 10)],
    ]) {
      expect(
        portfolioAllocationAt(
          positions: [holding('A', 10, 20)],
          trades: [],
          candles: {'A': prices},
          date: date,
        ),
        isNull,
      );
    }
  });

  test('prices use historical quote units and currency conversion', () {
    final previousRates = Map<String, double>.from(allRatesFromUsd);
    addTearDown(() => allRatesFromUsd = previousRates);
    allRatesFromUsd = {'USD': 1, 'GBP': .8};
    final result = portfolioAllocationAt(
      positions: [holding('A', 4, 20)],
      trades: [],
      candles: {
        'A': [candle('A', date, 1000, currency: 'GBp')],
      },
      date: date,
    )!;
    expect(result.single.value, 50);
  });

  test('a date before the first purchase has no allocation', () {
    expect(
      portfolioAllocationAt(
        positions: [holding('NEW', 5, 10)],
        trades: [trade('NEW', 5, later)],
        candles: {},
        date: date,
      ),
      isEmpty,
    );
  });
}
