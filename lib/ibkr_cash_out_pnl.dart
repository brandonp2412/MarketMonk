import 'package:market_monk/ibkr_api.dart';

class IbkrCashOutPnl {
  final double currentValue;
  final double netContributions;
  final double profitLoss;

  const IbkrCashOutPnl({
    required this.currentValue,
    required this.netContributions,
    required this.profitLoss,
  });

  double? get percent =>
      netContributions > 0 ? profitLoss / netContributions * 100 : null;
}

/// Computes whole-account cash-out P/L from inception.
///
/// Position-level unrealized P/L is based on remaining holdings' average cost,
/// so it does not answer what the entire account would be up or down after
/// liquidation. Infer external contributions from NAV and cumulative TWR,
/// then compare them with current net liquidation.
IbkrCashOutPnl calculateIbkrCashOutPnl(
  IbkrPerformanceSeries performance,
  IbkrAccountValue currentValue,
) {
  if (!currentValue.value.isFinite || currentValue.value < 0) {
    throw StateError('Current IBKR account value is invalid');
  }
  if (performance.currency.toUpperCase() != currentValue.currency.toUpperCase()) {
    throw StateError('IBKR performance and account currencies do not match');
  }

  final startNav = performance.startNav;
  if (startNav == null || !startNav.isFinite || startNav < 0) {
    throw StateError('IBKR PortfolioAnalyst start NAV is invalid');
  }
  if (startNav.abs() >= 0.01) {
    throw StateError(
      'Cash-out P/L requires IBKR PortfolioAnalyst history from account inception',
    );
  }
  if (performance.nav.isEmpty ||
      performance.nav.length != performance.returns.length) {
    throw StateError('IBKR PortfolioAnalyst NAV and return history is invalid');
  }

  var netContributions = startNav;
  var previousNav = startNav;
  var previousCumulativeReturn = 0.0;

  for (var index = 0; index < performance.nav.length; index++) {
    final nav = performance.nav[index];
    final cumulativeReturn = performance.returns[index];
    if (!nav.isFinite || nav < 0) {
      throw StateError('IBKR PortfolioAnalyst NAV history is invalid');
    }
    if (!cumulativeReturn.isFinite || cumulativeReturn <= -1) {
      throw StateError('IBKR PortfolioAnalyst return history is invalid');
    }

    final previousFactor = 1 + previousCumulativeReturn;
    final currentFactor = 1 + cumulativeReturn;
    if (previousFactor <= 0 || currentFactor <= 0) {
      throw StateError('IBKR PortfolioAnalyst return factor is invalid');
    }

    final periodFactor = currentFactor / previousFactor;
    final cashFlow = nav / periodFactor - previousNav;
    if (!cashFlow.isFinite) {
      throw StateError('IBKR PortfolioAnalyst cash-flow inference is invalid');
    }

    netContributions += cashFlow;
    previousNav = nav;
    previousCumulativeReturn = cumulativeReturn;
  }

  final profitLoss = currentValue.value - netContributions;
  if (!netContributions.isFinite || !profitLoss.isFinite) {
    throw StateError('IBKR cash-out P/L is invalid');
  }

  return IbkrCashOutPnl(
    currentValue: currentValue.value,
    netContributions: netContributions,
    profitLoss: profitLoss,
  );
}
