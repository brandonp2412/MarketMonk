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
  test('tiny allocation percentages remain readable', () {
    expect(formatCashAllocationPercent(0.02), '0.02');
    expect(formatCashAllocationPercent(25), '25.0');
    expect(formatCashAllocationPercent(100), '100.0');
  });

  test('broker USD exchange rate preserves tiny cash balances', () {
    final savedRates = Map<String, double>.from(allRatesFromUsd);
    addTearDown(() => allRatesFromUsd = savedRates);
    for (final summary in [
      const {
        'netliquidation': {'value': 100000.0, 'currency': 'NZD'},
        'totalcashvalue': {'value': 20.0, 'currency': 'NZD'},
        'netliquidationbycurrency:usd': {'value': 1.0, 'currency': 'USD'},
      },
      const {
        'netliquidation': {'amount': 100000.0, 'currency': 'NZD'},
        'totalcashvalue': {'amount': 20.0, 'currency': 'NZD'},
        'netliquidationbycurrency:usd': {'amount': 1.0, 'currency': 'USD'},
      },
    ]) {
      final snapshot = IbkrPortfolioSnapshot(
        account: 'test',
        positions: const [],
        summary: summary,
        ledger: const {
          'BASE': {'cashbalance': 20.0},
          'USD': {'exchangerate': 1.8},
        },
      );
      cacheIbkrAccountExchangeRate(snapshot);
      expect(allRatesFromUsd['NZD'], 1.8);
      final cachedCash = ibkrCashBalanceForCache(snapshot)!;
      expect(cachedCash.currency, 'USD');
      expect(cachedCash.value, closeTo(20 / 1.8, 0.0001));
      expect(
        ibkrCashValueUsd(
          cashBalance: cachedCash,
          netLiquidation: snapshot.netLiquidation,
          netLiquidationUsd: null,
        ),
        closeTo(20 / 1.8, 0.0001),
      );
    }
  });

  test('missing broker FX keeps native cash for later conversion', () {
    final snapshot = IbkrPortfolioSnapshot(
      account: 'test',
      positions: const [],
      summary: const {
        'totalcashvalue': {'value': 25.0, 'currency': 'NZD'},
        'netliquidation': {'value': 1000.0, 'currency': 'NZD'},
      },
      ledger: const {},
    );
    final cash = ibkrCashBalanceForCache(snapshot)!;
    expect(cash.currency, 'NZD');
    expect(cash.value, 25);
  });

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

  test('dated FX values holdings and reconciles cash to historical NAV', () {
    final result = portfolioAllocationAt(
      positions: [holding('GBP', 1, 20)],
      trades: [],
      candles: {
        'GBP': [candle('GBP', date, 1000, currency: 'GBp')],
      },
      date: date,
      currencyRates: {'GBP': 1},
      historicalAccountValueUsd: 100,
    )!;
    expect(
      {for (final holding in result) holding.symbol: holding.value},
      {'GBP': 10, 'CASH': 90},
    );
    expect(result.last.isCash, isTrue);
    expect(
      portfolioAllocationAt(
        positions: [holding('GBP', 1, 20)],
        trades: [],
        candles: {
          'GBP': [candle('GBP', date, 1000, currency: 'GBp')],
        },
        date: date,
        currencyRates: {'USD': 1},
        historicalAccountValueUsd: 100,
      ),
      isNull,
    );
  });

  test('historical broker NAV can include negative margin cash', () {
    final allocation = portfolioAllocationAt(
      positions: [holding('A', 10, 100)],
      trades: [],
      candles: {
        'A': [candle('A', date, 100)],
      },
      date: date,
      currencyRates: {'USD': 1},
      historicalAccountValueUsd: 990,
    )!;
    expect(allocation, hasLength(2));
    expect(allocation.first.value, 1000);
    expect(allocation.last.symbol, 'CASH');
    expect(allocation.last.isCash, isTrue);
    expect(allocation.last.value, -10);
    expect(allocation.fold<double>(0, (sum, item) => sum + item.value), 990);
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
