class ProvisionalHolding {
  final double shares;
  final Map<DateTime, double> closesUsd;

  const ProvisionalHolding({required this.shares, required this.closesUsd});
}

class ProvisionalPortfolioPoint {
  final DateTime date;
  final double valueUsd;

  const ProvisionalPortfolioPoint(this.date, this.valueUsd);
}

/// Extends a dated broker NAV using only observed price changes of current holdings.
/// Cash, unpriced assets and share quantities are held constant.
List<ProvisionalPortfolioPoint> projectPortfolioFromCloses({
  required DateTime brokerDate,
  required double brokerNavUsd,
  required List<ProvisionalHolding> holdings,
  required DateTime latestDate,
}) {
  if (holdings.isEmpty || !brokerNavUsd.isFinite || brokerNavUsd <= 0) {
    return [];
  }
  final baselines = <double>[];
  for (final holding in holdings) {
    if (!holding.shares.isFinite || holding.closesUsd.isEmpty) return [];
    final eligible = holding.closesUsd.entries
        .where(
          (entry) =>
              !entry.key.isAfter(brokerDate) &&
              brokerDate.difference(entry.key).inDays <= 4 &&
              entry.value.isFinite &&
              entry.value > 0,
        )
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (eligible.isEmpty) return [];
    baselines.add(eligible.last.value);
  }

  final dates = holdings
      .expand((holding) => holding.closesUsd.keys)
      .where(
        (date) => date.isAfter(brokerDate) && !date.isAfter(latestDate),
      )
      .toSet()
      .toList()
    ..sort();
  final result = <ProvisionalPortfolioPoint>[];
  for (final date in dates) {
    var delta = 0.0;
    var complete = true;
    for (var i = 0; i < holdings.length; i++) {
      final holding = holdings[i];
      final recent = holding.closesUsd.entries
          .where(
            (entry) =>
                !entry.key.isAfter(date) &&
                date.difference(entry.key).inDays <= 4 &&
                entry.value.isFinite &&
                entry.value > 0,
          )
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (recent.isEmpty) {
        complete = false;
        break;
      }
      delta += holding.shares * (recent.last.value - baselines[i]);
    }
    final value = brokerNavUsd + delta;
    if (complete && value.isFinite && value > 0) {
      result.add(ProvisionalPortfolioPoint(date, value));
    }
  }
  return result;
}
