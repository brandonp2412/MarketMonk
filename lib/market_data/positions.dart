part of '../market_data.dart';

/// A computed portfolio position derived from trades and candles.
class Position {
  final String symbol;
  final String name;

  /// ISO 4217 currency that [avgCost] and [currentPrice] are denominated in.
  final String nativeCurrency;

  final double netShares; // SUM(quantity) across all trades

  /// Weighted average buy price in [nativeCurrency].
  final double avgCost;

  /// Latest candle close price in [nativeCurrency].
  final double currentPrice;

  final DateTime firstBuyDate;
  final DateTime lastBuyDate;
  final double? brokerMarketValue;
  final double? brokerUnrealizedPL;
  final double? brokerRealizedPL;
  final double? historicalCostBasisUsd;

  Position({
    required this.symbol,
    required this.name,
    required this.nativeCurrency,
    required this.netShares,
    required this.avgCost,
    required this.currentPrice,
    required this.firstBuyDate,
    required this.lastBuyDate,
    this.brokerMarketValue,
    this.brokerUnrealizedPL,
    this.brokerRealizedPL,
    this.historicalCostBasisUsd,
  });

  /// Conversion factor from [nativeCurrency] to USD.
  /// All monetary getters below return values in USD so that
  /// [fmtCurrency] (which applies USD → displayCurrency) works correctly.
  double get _nativeToUsd => 1.0 / requireUsdRate(nativeCurrency);

  /// Percentage gain/loss relative to average cost. Currency-agnostic.
  double get change => historicalCostBasisUsd == null
      ? safePercentChange(avgCost, currentPrice)
      : safePercentChange(costBasis, currentValue);

  /// Current market value in USD.
  double get currentValue =>
      (brokerMarketValue ?? netShares * currentPrice) * _nativeToUsd;

  /// Total cost basis in USD.
  double get costBasis =>
      historicalCostBasisUsd ?? netShares * avgCost * _nativeToUsd;

  /// Unrealised profit/loss in USD.
  double get unrealizedPL =>
      historicalCostBasisUsd != null || brokerUnrealizedPL == null
          ? currentValue - costBasis
          : brokerUnrealizedPL! * _nativeToUsd;

  /// IBKR realized P/L for the current day, converted to USD when available.
  double? get realizedToday =>
      brokerRealizedPL == null ? null : brokerRealizedPL! * _nativeToUsd;
}

/// Converts current IBKR stock positions into MarketMonk positions while using
/// local trades only for display names and purchase dates.
Future<List<Position>> computeIbkrPositions(
  List<IbkrPosition> brokerPositions,
  List<Trade> localTrades,
) async {
  final stockPositions = brokerPositions
      .where(
        (position) => position.securityType == 'STK' && position.quantity > 0,
      )
      .toList();

  for (final position in stockPositions) {
    final nativeCurrency = cacheSymbolMeta(position.symbol, position.currency);
    if (nativeCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(nativeCurrency)) {
      await _fetchAndCacheRate(nativeCurrency);
    }
    requireUsdRate(nativeCurrency);
  }

  return stockPositions.map((broker) {
    final trades =
        localTrades.where((trade) => trade.symbol == broker.symbol).toList();
    final buys = trades.where((trade) => trade.quantity > 0).toList();
    final now = DateTime.now();
    final firstBuyDate = buys.isEmpty
        ? now
        : buys.map((trade) => trade.tradeDate).reduce(
              (firstDate, secondDate) =>
                  firstDate.isBefore(secondDate) ? firstDate : secondDate,
            );
    final lastBuyDate = buys.isEmpty
        ? now
        : buys.map((trade) => trade.tradeDate).reduce(
              (firstDate, secondDate) =>
                  firstDate.isAfter(secondDate) ? firstDate : secondDate,
            );
    final currentPrice = broker.marketPrice ?? broker.averageCost ?? 0.0;
    final avgCost = broker.averageCost ?? currentPrice;
    final historyVerified = trades.isNotEmpty &&
        trades.every(
          (trade) =>
              trade.rawCurrency != null &&
              (trade.usdRateAtTrade != null ||
                  normalizedQuoteCurrency(trade.rawCurrency!) == 'USD'),
        ) &&
        ((trades.fold<double>(0, (sum, trade) => sum + trade.quantity)) -
                    broker.quantity)
                .abs() <
            0.00001;
    final historicalCostBasisUsd = historyVerified
        ? _averageCostForOpenPosition(
              trades,
              priceForTrade: (trade) => tradeAmountUsd(trade, trade.price),
            ) *
            broker.quantity
        : null;
    return Position(
      symbol: broker.symbol,
      name: trades.isEmpty ? broker.symbol : trades.first.name,
      nativeCurrency: broker.currency,
      netShares: broker.quantity,
      avgCost: avgCost,
      currentPrice: currentPrice,
      firstBuyDate: firstBuyDate,
      lastBuyDate: lastBuyDate,
      brokerMarketValue: broker.marketValue,
      brokerUnrealizedPL: broker.unrealizedPnl,
      brokerRealizedPL: broker.realizedPnl,
      historicalCostBasisUsd: historicalCostBasisUsd,
    );
  }).toList();
}

double _averageCostForOpenPosition(
  List<Trade> trades, {
  double Function(Trade)? priceForTrade,
}) {
  final ordered = List<Trade>.from(trades)
    ..sort((firstTrade, secondTrade) {
      final byDate = firstTrade.tradeDate.compareTo(secondTrade.tradeDate);
      return byDate != 0 ? byDate : firstTrade.id.compareTo(secondTrade.id);
    });

  var openShares = 0.0;
  var averageCost = 0.0;
  for (final trade in ordered) {
    final quantity = trade.quantity;
    if (quantity > 0) {
      final previousLongShares = openShares > 0 ? openShares : 0.0;
      final shortShares = openShares < 0 ? -openShares : 0.0;
      final openingShares =
          quantity > shortShares ? quantity - shortShares : 0.0;
      openShares += quantity;
      if (openShares > 0) {
        averageCost = previousLongShares > 0
            ? (previousLongShares * averageCost +
                    openingShares *
                        (priceForTrade?.call(trade) ?? trade.price)) /
                openShares
            : (priceForTrade?.call(trade) ?? trade.price);
      } else {
        averageCost = 0.0;
      }
    } else if (quantity < 0) {
      openShares += quantity;
      if (openShares <= 0) averageCost = 0.0;
    }
  }
  return averageCost;
}

/// Computes open positions from a list of trades and a symbol→latestPrice map.
/// Only returns positions with net shares > 0 (i.e. not fully closed).
List<Position> computePositions(
  List<Trade> trades,
  Map<String, double> latestPrices, {
  Map<String, String> nativeCurrencies = const {},
}) {
  final bySymbol = <String, List<Trade>>{};
  for (final trade in trades) {
    bySymbol.putIfAbsent(trade.symbol, () => []).add(trade);
  }

  final positions = <Position>[];
  for (final entry in bySymbol.entries) {
    final symbol = entry.key;
    final symbolTrades = entry.value;
    final netShares = symbolTrades.fold(
      0.0,
      (sum, trade) => sum + trade.quantity,
    );
    if (netShares <= 0) continue;

    final nativeCurrency =
        nativeCurrencies[symbol] ?? _symbolCurrencies[symbol] ?? 'UNKNOWN';
    if (_symbolsWithCurrencyChanges.contains(symbol) &&
        symbolTrades.any((trade) => trade.rawCurrency == null)) {
      throw StateError(
        '$symbol changed quotation currency. Confirm the original currency '
        'and unit of legacy trades before calculating its cost basis.',
      );
    }
    final legacyUnits = symbolTrades.every(
      (trade) => trade.rawCurrency == null,
    );
    final avgCostUsd = legacyUnits
        ? null
        : _averageCostForOpenPosition(
            symbolTrades,
            priceForTrade: (trade) => tradeAmountUsd(trade, trade.price),
          );
    final buyTrades = symbolTrades.where((trade) => trade.quantity > 0);
    final dates = buyTrades.map((trade) => trade.tradeDate).toList();
    final firstBuyDate = dates.isNotEmpty
        ? dates.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final lastBuyDate = dates.isNotEmpty
        ? dates.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now();

    final nativeAvgCost = avgCostUsd == null
        ? _averageCostForOpenPosition(symbolTrades) / symbolCentDivisor(symbol)
        : avgCostUsd * requireUsdRate(nativeCurrency);
    final currentPrice = latestPrices.containsKey(symbol)
        ? latestPrices[symbol]! / symbolCentDivisor(symbol)
        : nativeAvgCost;
    positions.add(
      Position(
        symbol: symbol,
        name: symbolTrades.first.name,
        nativeCurrency: nativeCurrency,
        netShares: netShares,
        avgCost: nativeAvgCost,
        currentPrice: currentPrice,
        historicalCostBasisUsd:
            avgCostUsd == null ? null : netShares * avgCostUsd,
        firstBuyDate: firstBuyDate,
        lastBuyDate: lastBuyDate,
      ),
    );
  }
  return positions;
}

/// Returns the latest candle close price per symbol.
/// Uses an INNER JOIN with a GROUP BY subquery so the DB returns exactly
/// one row per symbol instead of all historical candles.
