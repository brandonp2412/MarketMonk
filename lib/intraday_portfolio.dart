import 'package:market_monk/intraday_market_data.dart';

/// A trade with a signed share change and execution price expressed in USD.
class IntradayPortfolioTrade {
  final DateTime date;
  final double quantity;
  final double priceUsd;
  const IntradayPortfolioTrade(this.date, this.quantity, this.priceUsd);
}

/// A current holding and its intraday prices expressed in USD per share.
class IntradayPortfolioHolding {
  /// Signed current share count, including short positions.
  final double quantity;

  final bool constantPrice;
  final List<IntradayPortfolioTrade> trades;

  /// Observed prices by UTC timestamp, after currency and cent conversion.
  final Map<DateTime, double> pricesUsd;

  /// Retains current quantities when reconstructing the selected period.
  const IntradayPortfolioHolding({
    required this.quantity,
    this.constantPrice = false,
    this.trades = const [],
    required this.pricesUsd,
  });

  /// Converts provider candles using the quote currency's USD exchange rate.
  factory IntradayPortfolioHolding.fromSeries(
    IntradaySeries series, {
    required double quantity,
    required double currencyPerUsd,
    required double centDivisor,
    List<IntradayPortfolioTrade> trades = const [],
  }) =>
      IntradayPortfolioHolding(
        quantity: quantity,
        trades: trades,
        constantPrice: series.isDaily && series.candles.length == 1,
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
/// Replays known trades at their recorded timestamps, with their cash flows.
/// Unknown cash, unpriced assets and exchange rates remain anchored to current
/// NAV. When a trade history is incomplete, its missing quantity is treated as
/// an opening position rather than inventing transactions.
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
  final prices = <int, double>{
    for (final (index, holding) in holdings.indexed)
      if (holding.constantPrice && holding.pricesUsd.length == 1)
        index: holding.pricesUsd.values.single,
  };
  final values = <IntradayPortfolioValue>[];
  final orderedTrades = [
    for (final holding in holdings)
      for (final trade in holding.trades) (holding, trade),
  ]..sort((a, b) => a.$2.date.compareTo(b.$2.date));
  final quantities = [
    for (final holding in holdings)
      holding.quantity -
          holding.trades.fold<double>(
            0,
            (sum, trade) => sum + trade.quantity,
          ),
  ];
  var cashFlowUsd = 0.0;
  var tradeIndex = 0;
  for (final date in sortedDates) {
    for (var i = 0; i < holdings.length; i++) {
      final price = holdings[i].pricesUsd[date];
      if (price != null && price.isFinite && price > 0) prices[i] = price;
    }
    while (tradeIndex < orderedTrades.length &&
        !orderedTrades[tradeIndex].$2.date.isAfter(date)) {
      final (holding, trade) = orderedTrades[tradeIndex++];
      final index = holdings.indexOf(holding);
      quantities[index] += trade.quantity;
      cashFlowUsd -= trade.quantity * trade.priceUsd;
    }
    if (prices.length != holdings.length) continue;
    final value = holdings.indexed.fold<double>(
      cashFlowUsd,
      (total, item) => total + quantities[item.$1] * prices[item.$1]!,
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
