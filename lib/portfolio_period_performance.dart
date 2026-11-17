class PortfolioPeriodPerformance {
  final double gain;
  final double basis;

  const PortfolioPeriodPerformance(this.gain, this.basis);

  double get percent => gain / basis * 100;
}

PortfolioPeriodPerformance? portfolioPeriodPerformance({
  required double startingValue,
  required double endingValue,
  required DateTime startDate,
  required DateTime endDate,
  required Map<DateTime, double> cashFlows,
}) {
  final periodMillis = endDate.difference(startDate).inMilliseconds;
  if (periodMillis <= 0 ||
      !startingValue.isFinite ||
      !endingValue.isFinite ||
      startingValue < 0 ||
      endingValue < 0) {
    return null;
  }

  var externalFlows = 0.0;
  for (final flow in cashFlows.entries) {
    if (!flow.key.isAfter(startDate) || flow.key.isAfter(endDate)) {
      continue;
    }
    if (!flow.value.isFinite) return null;
    externalFlows += flow.value;
  }

  final gain = endingValue - startingValue - externalFlows;
  final basis = endingValue - gain;
  if (!gain.isFinite || !basis.isFinite || basis <= 0) return null;
  return PortfolioPeriodPerformance(gain, basis);
}
