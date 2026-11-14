import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/utils.dart';

IbkrAccountValue? ibkrCashBalanceForCache(IbkrPortfolioSnapshot snapshot) {
  final cash = snapshot.cashBalance;
  if (cash == null || cash.currency == 'USD') return cash;
  if (snapshot.netLiquidation?.currency != cash.currency) return cash;
  final rate = snapshot.usdExchangeRateInBase;
  if (rate == null) return cash;
  return IbkrAccountValue(value: cash.value / rate, currency: 'USD');
}

String formatCashAllocationPercent(double percent) =>
    percent.abs() < 1 ? percent.toStringAsFixed(2) : percent.toStringAsFixed(1);

double? ibkrCashValueUsd({
  required IbkrAccountValue? cashBalance,
  required IbkrAccountValue? netLiquidation,
  required double? netLiquidationUsd,
}) {
  if (cashBalance == null ||
      cashBalance.currency.isEmpty ||
      !cashBalance.value.isFinite) return null;
  if (cashBalance.currency == 'USD') return cashBalance.value;
  if (netLiquidation?.currency == cashBalance.currency &&
      netLiquidation!.value.isFinite &&
      netLiquidation.value > 0 &&
      netLiquidationUsd != null &&
      netLiquidationUsd.isFinite &&
      netLiquidationUsd > 0) {
    return cashBalance.value * netLiquidationUsd / netLiquidation.value;
  }
  final rate = allRatesFromUsd[cashBalance.currency];
  if (rate == null || !rate.isFinite || rate <= 0) return null;
  return cashBalance.value / rate;
}

class PortfolioAllocation {
  final String symbol;
  final String name;
  final double value;
  final bool isCash;

  const PortfolioAllocation(
    this.symbol,
    this.name,
    this.value, {
    this.isCash = false,
  });
}

Map<String, double> portfolioSharesAt({
  required List<Position> positions,
  required List<Trade> trades,
  required DateTime date,
}) {
  final shares = {
    for (final position in positions) position.symbol: position.netShares,
  };
  for (final trade in trades) {
    final day = DateTime(
      trade.tradeDate.year,
      trade.tradeDate.month,
      trade.tradeDate.day,
    );
    if (day.isAfter(date)) {
      shares[trade.symbol] = (shares[trade.symbol] ?? 0) - trade.quantity;
    }
  }
  return shares;
}

List<PortfolioAllocation>? portfolioAllocationAt({
  required List<Position> positions,
  required List<Trade> trades,
  required Map<String, List<StoredCandle>> candles,
  required DateTime? date,
  double? cashValueUsd,
  double? historicalAccountValueUsd,
  Map<String, double>? currencyRates,
}) {
  if (date == null) {
    return [
      for (final position in positions)
        PortfolioAllocation(
          position.symbol,
          position.name,
          position.currentValue,
        ),
      if (cashValueUsd != null && cashValueUsd.isFinite && cashValueUsd > 0)
        PortfolioAllocation('CASH', 'Cash', cashValueUsd, isCash: true),
    ];
  }
  final shares =
      portfolioSharesAt(positions: positions, trades: trades, date: date);
  final names = {
    for (final trade in trades) trade.symbol: trade.name,
    for (final position in positions) position.symbol: position.name,
  };
  final allocations = <PortfolioAllocation>[];
  for (final entry in shares.entries) {
    if (entry.value < -1e-6) return null;
    if (entry.value <= 1e-6) continue;
    StoredCandle? baseline;
    for (final candle in candles[entry.key] ?? <StoredCandle>[]) {
      if (!candle.date.isAfter(date) &&
          (baseline == null || candle.date.isAfter(baseline.date)))
        baseline = candle;
    }
    if (baseline == null || date.difference(baseline.date).inDays > 7)
      return null;
    try {
      final currency = normalizedQuoteCurrency(
        baseline.rawCurrency ?? symbolCurrency(entry.key),
      );
      final rate = currencyRates == null
          ? requireUsdRate(currency)
          : currencyRates[currency];
      if (rate == null || !rate.isFinite || rate <= 0) return null;
      final price = baseline.close / candleCentDivisor(baseline) / rate;
      final value = entry.value * price;
      if (!value.isFinite || value < 0) return null;
      allocations.add(
        PortfolioAllocation(entry.key, names[entry.key] ?? entry.key, value),
      );
    } on StateError {
      return null;
    }
  }
  if (historicalAccountValueUsd != null) {
    if (!historicalAccountValueUsd.isFinite || historicalAccountValueUsd < 0) {
      return null;
    }
    final holdingsValue = allocations.fold<double>(
      0,
      (sum, holding) => sum + holding.value,
    );
    final cash = historicalAccountValueUsd - holdingsValue;
    // A broker's net liquidation value can be lower than its gross holdings:
    // a margin debit (or a small quote/NAV mismatch) is valid negative cash.
    // Preserve that debit instead of hiding the entire historical period.
    if (cash.abs() > 0.01) {
      allocations.add(PortfolioAllocation('CASH', 'Cash', cash, isCash: true));
    }
  }
  return allocations;
}
