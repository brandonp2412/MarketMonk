import 'package:market_monk/intraday_market_data.dart';

/// A current holding and its intraday prices expressed in USD per share.
class IntradayPortfolioHolding {
  /// Signed current share count, including short positions.
  final double quantity;

  /// Observed prices by UTC timestamp, after currency and cent conversion.
  final Map<DateTime, double> pricesUsd;

  /// Retains current quantities when reconstructing the selected period.
  const IntradayPortfolioHolding({
    required this.quantity,
    required this.pricesUsd,
  });

  /// Converts provider candles using the quote currency's USD exchange rate.
  factory IntradayPortfolioHolding.fromSeries(
    IntradaySeries series, {
    required double quantity,
    required double currencyPerUsd,
    required double centDivisor,
  }) =>
      IntradayPortfolioHolding(
        quantity: quantity,
        pricesUsd: {
          for (final candle in series.candles)
            candle.date: candle.close / centDivisor / currencyPerUsd,
        },
      );
}

/// A reconstructed account value at an observed market timestamp.
class IntradayPortfolioValue {
  /// UTC market timestamp, without interpolated observations.
  final DateTime date;

  /// Account value in USD with non-priced assets held constant.
  final double valueUsd;

  /// Stores one reconstructed value for rendering and comparisons.
  const IntradayPortfolioValue(this.date, this.valueUsd);
}

/// Reconstructs current holdings' price changes around the current account NAV.
///
/// Quantities, cash, unpriced assets, and exchange rates stay constant. These
/// values estimate market movement rather than broker historical NAV or TWR.
/// Observations start once every priced holding has a known close; afterwards
/// a holding retains its last observed close until its next market bar.
List<IntradayPortfolioValue> buildIntradayPortfolio({
  required List<IntradayPortfolioHolding> holdings,
  required double currentValueUsd,
}) {
  if (holdings.isEmpty || !currentValueUsd.isFinite) return [];
  final dates = holdings.expand((holding) => holding.pricesUsd.keys).toSet()
    ..removeWhere((date) => !date.isUtc);
  final sortedDates = dates.toList()..sort();
  final prices = <int, double>{};
  final values = <IntradayPortfolioValue>[];
  for (final date in sortedDates) {
    for (var i = 0; i < holdings.length; i++) {
      final price = holdings[i].pricesUsd[date];
      if (price != null && price.isFinite && price > 0) prices[i] = price;
    }
    if (prices.length != holdings.length) continue;
    final value = holdings.indexed.fold<double>(
      0,
      (total, item) => total + item.$2.quantity * prices[item.$1]!,
    );
    if (value.isFinite) values.add(IntradayPortfolioValue(date, value));
  }
  if (values.isEmpty) return [];
  final residual = currentValueUsd - values.last.valueUsd;
  return [
    for (final value in values)
      IntradayPortfolioValue(value.date, value.valueUsd + residual),
  ];
}
