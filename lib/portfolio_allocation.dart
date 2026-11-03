import 'package:market_monk/database.dart';
import 'package:market_monk/utils.dart';

class PortfolioAllocation {
  final String symbol;
  final String name;
  final double value;

  const PortfolioAllocation(this.symbol, this.name, this.value);
}

List<PortfolioAllocation>? portfolioAllocationAt({
  required List<Position> positions,
  required List<Trade> trades,
  required Map<String, List<StoredCandle>> candles,
  required DateTime? date,
}) {
  if (date == null) {
    return [
      for (final position in positions)
        PortfolioAllocation(
          position.symbol,
          position.name,
          position.currentValue,
        ),
    ];
  }
  final shares = {
    for (final position in positions) position.symbol: position.netShares,
  };
  final names = {
    for (final trade in trades) trade.symbol: trade.name,
    for (final position in positions) position.symbol: position.name,
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
      final price = baseline.close /
          candleCentDivisor(baseline) /
          requireUsdRate(currency);
      final value = entry.value * price;
      if (!value.isFinite || value < 0) return null;
      allocations.add(
        PortfolioAllocation(entry.key, names[entry.key] ?? entry.key, value),
      );
    } on StateError {
      return null;
    }
  }
  return allocations;
}
