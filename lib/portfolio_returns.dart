import 'package:market_monk/ibkr_api.dart';

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

double? accountNetAssetValueAt(
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
  return value.isFinite && value >= 0 ? value : null;
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

DateTime? portfolioReturnCutoff(int period, DateTime now) => switch (period) {
      0 => null,
      >= 1 && <= 5 => DateTime(now.year - (6 - period), now.month, now.day),
      6 => DateTime(now.year, now.month - 6, now.day),
      7 => DateTime(now.year, now.month - 3, now.day),
      8 => DateTime(now.year, now.month - 1, now.day),
      9 => DateTime(now.year, now.month, now.day - 7),
      10 => DateTime(now.year, now.month, now.day - 1),
      11 => DateTime(now.year, now.month - 2, now.day),
      12 => DateTime(now.year, now.month, now.day - 14),
      _ => DateTime(now.year, now.month, now.day - 1),
    };
