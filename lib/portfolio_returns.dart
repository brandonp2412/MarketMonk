import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/intraday_portfolio.dart';

class PortfolioReturn {
  final double gain;
  final double basis;

  const PortfolioReturn(this.gain, this.basis);

  double get percent => basis > 0 ? gain / basis * 100 : 0;
}

PortfolioReturn? accountPeriodReturn(
  IbkrPerformanceSeries history,
  double currentValue,
  DateTime cutoff,
) {
  if (history.dates.length != history.nav.length ||
      history.returns.length != history.nav.length ||
      history.nav.isEmpty) return null;
  var start = -1;
  for (var i = 0; i < history.dates.length; i++) {
    if (!history.dates[i].isAfter(cutoff)) start = i;
  }
  if (start < 0) return null;
  var basis = history.nav[start];
  for (var i = start + 1; i < history.nav.length; i++) {
    final previousFactor = 1 + history.returns[i - 1];
    final factor = 1 + history.returns[i];
    if (previousFactor <= 0 || factor <= 0) return null;
    basis += history.nav[i] * previousFactor / factor - history.nav[i - 1];
  }
  if (!basis.isFinite || !currentValue.isFinite) return null;
  return PortfolioReturn(currentValue - basis, basis);
}

int? accountNetAssetValueIndexAt(
  IbkrPerformanceSeries history,
  DateTime cutoff,
) {
  if (history.dates.length != history.nav.length || history.nav.isEmpty) {
    return null;
  }
  var selectedIndex = -1;
  for (var index = 0; index < history.dates.length; index++) {
    final date = history.dates[index];
    if (!date.isAfter(cutoff) &&
        (selectedIndex < 0 || date.isAfter(history.dates[selectedIndex]))) {
      selectedIndex = index;
    }
  }
  if (selectedIndex < 0 ||
      cutoff.difference(history.dates[selectedIndex]).inDays > 7) {
    return null;
  }
  final value = history.nav[selectedIndex];
  return value.isFinite && value >= 0 ? selectedIndex : null;
}

double? accountNetAssetValueAt(
  IbkrPerformanceSeries history,
  DateTime cutoff,
) {
  final index = accountNetAssetValueIndexAt(history, cutoff);
  return index == null ? null : history.nav[index];
}

PortfolioReturn? openHoldingPeriodReturn({
  required double currentValue,
  required double currentShares,
  required double baselinePrice,
  required DateTime cutoff,
  required List<({DateTime date, double quantity, double price})> trades,
}) {
  var shares = 0.0;
  var basis = 0.0;
  for (final trade in trades) {
    final date = DateTime(trade.date.year, trade.date.month, trade.date.day);
    if (!date.isAfter(cutoff)) {
      shares += trade.quantity;
      basis = shares * baselinePrice;
    } else if (trade.quantity > 0) {
      shares += trade.quantity;
      basis += trade.quantity * trade.price;
    } else {
      if (shares <= 0 || shares + trade.quantity < -1e-6) return null;
      basis *= (shares + trade.quantity) / shares;
      shares += trade.quantity;
    }
  }
  if ((shares - currentShares).abs() > 1e-6 || shares <= 0) return null;
  return PortfolioReturn(currentValue - basis, basis);
}

/// Index of the first legacy intraday return period (unused by the fortnightly picker).
const int firstIntradayPeriod = 13;

/// Stable, consecutive 14-day slider stops (Now, 2W, 4W, ...).
/// Negative IDs avoid conflicting with historical period IDs in saved data.
/// The broker performance cache currently covers at most one year.
List<int> portfolioFortnightlyPeriods(DateTime now, DateTime? firstDate) {
  if (firstDate == null || !firstDate.isBefore(now)) return const [0];
  // Compare calendar dates in UTC to avoid losing a day at DST boundaries.
  final today = DateTime.utc(now.year, now.month, now.day);
  final oldest = DateTime.utc(firstDate.year, firstDate.month, firstDate.day);
  final count = (today.difference(oldest).inDays ~/ 14).clamp(0, 26);
  return [
    0,
    for (var fortnight = 1; fortnight <= count; fortnight++) -fortnight - 1,
  ];
}

/// Fortnightly stops use IDs -2, -3, ... with consecutive 14-day cutoffs.
/// Legacy IDs remain supported for migrated caches and existing callers.
/// Returns null for 'Now' (ID 0).
DateTime? portfolioReturnCutoff(int period, DateTime now) => switch (period) {
      0 => null,
      <= -2 => DateTime(now.year, now.month, now.day - (-period - 1) * 14),
      >= 1 && <= 5 => DateTime(now.year - (6 - period), now.month, now.day),
      6 => DateTime(now.year, now.month - 6, now.day),
      7 => DateTime(now.year, now.month - 3, now.day),
      8 => DateTime(now.year, now.month - 1, now.day),
      9 => DateTime(now.year, now.month, now.day - 7),
      10 => DateTime(now.year, now.month, now.day - 1),
      11 => DateTime(now.year, now.month - 2, now.day),
      12 => DateTime(now.year, now.month, now.day - 14),
      13 => now.subtract(const Duration(hours: 12)),
      14 => now.subtract(const Duration(hours: 6)),
      15 => now.subtract(const Duration(hours: 2)),
      16 => now.subtract(const Duration(hours: 1)),
      _ => DateTime(now.year, now.month, now.day - 1),
    };

/// USD value of an intraday portfolio at or before [cutoff], or null when
/// [values] starts after the cutoff.
///
/// [values] must be in ascending date order.
double? intradayAccountValueAt(
  List<IntradayPortfolioValue> values,
  DateTime cutoff,
) {
  double? value;
  for (final point in values) {
    if (point.date.isAfter(cutoff)) break;
    value = point.valueUsd;
  }
  return value;
}
