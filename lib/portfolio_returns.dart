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
