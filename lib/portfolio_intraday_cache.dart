import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/utils.dart';

/// Per-profile, on-disk intraday bars used by the portfolio period picker.
/// Persist holdings rather than derived NAV so a newer snapshot can re-anchor
/// the cached price changes without contacting the broker.
class CachedPortfolioIntraday {
  const CachedPortfolioIntraday({
    required this.positionsKey,
    required this.cachedAt,
    required this.holdings,
  });

  final String positionsKey;
  final DateTime cachedAt;
  final Map<String, IntradayPortfolioHolding> holdings;

  static String keyFor(List<Position> positions) {
    final symbols = [
      for (final position in positions)
        if (position.netShares != 0) '${position.symbol}:${position.netShares}',
    ]..sort();
    return symbols.join('|');
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'positionsKey': positionsKey,
        'cachedAt': cachedAt.toUtc().toIso8601String(),
        'holdings': {
          for (final entry in holdings.entries)
            entry.key: {
              'quantity': entry.value.quantity,
              'constantPrice': entry.value.constantPrice,
              'pricesUsd': [
                for (final price in entry.value.pricesUsd.entries)
                  [price.key.toUtc().toIso8601String(), price.value],
              ],
              'trades': [
                for (final trade in entry.value.trades)
                  [
                    trade.date.toUtc().toIso8601String(),
                    trade.quantity,
                    trade.priceUsd,
                  ],
              ],
            },
        },
      };

  factory CachedPortfolioIntraday.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported intraday portfolio cache');
    }
    final rawHoldings = json['holdings'] as Map<String, dynamic>;
    final holdings = <String, IntradayPortfolioHolding>{};
    for (final entry in rawHoldings.entries) {
      final value = entry.value as Map<String, dynamic>;
      holdings[entry.key] = IntradayPortfolioHolding(
        quantity: (value['quantity'] as num).toDouble(),
        constantPrice: value['constantPrice'] == true,
        pricesUsd: {
          for (final row in value['pricesUsd'] as List)
            DateTime.parse((row as List)[0] as String).toUtc():
                (row[1] as num).toDouble(),
        },
        trades: [
          for (final row in value['trades'] as List)
            IntradayPortfolioTrade(
              DateTime.parse((row as List)[0] as String).toUtc(),
              (row[1] as num).toDouble(),
              (row[2] as num).toDouble(),
            ),
        ],
      );
    }
    return CachedPortfolioIntraday(
      positionsKey: json['positionsKey'] as String,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      holdings: holdings,
    );
  }

  /// Reject cache from different holdings or an obsolete market session.
  bool isUsableFor(List<Position> positions, DateTime now) {
    if (positionsKey != keyFor(positions) || holdings.isEmpty) return false;
    final expectedSymbols = {
      for (final position in positions)
        if (position.netShares != 0) position.symbol,
    };
    if (holdings.keys.toSet().difference(expectedSymbols).isNotEmpty ||
        expectedSymbols.difference(holdings.keys.toSet()).isNotEmpty) {
      return false;
    }
    final age = now.difference(cachedAt);
    if (age.isNegative || age > const Duration(hours: 36)) return false;
    return holdings.values.every(
      (holding) =>
          holding.pricesUsd.isNotEmpty &&
          holding.quantity.isFinite &&
          holding.pricesUsd.keys.every((date) => date.isUtc) &&
          holding.pricesUsd.values.every(
            (price) => price.isFinite && price > 0,
          ),
    );
  }
}
