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

class ProvisionalQuote {
  final DateTime observedAt;
  final double priceUsd;

  const ProvisionalQuote({required this.observedAt, required this.priceUsd});
}

ProvisionalPortfolioPoint? projectPortfolioFromQuotes({
  required DateTime brokerDate,
  required double brokerNavUsd,
  required List<ProvisionalHolding> holdings,
  required List<ProvisionalQuote> quotes,
  required DateTime now,
}) {
  if (holdings.isEmpty ||
      holdings.length != quotes.length ||
      !brokerNavUsd.isFinite ||
      brokerNavUsd <= 0) return null;
  final newest = quotes.map((q) => q.observedAt).reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
  final oldest = quotes.map((q) => q.observedAt).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
  if (newest.isAfter(now) ||
      now.difference(newest) > const Duration(days: 4) ||
      newest.difference(oldest) > const Duration(minutes: 30)) return null;
  final utcDate = newest.toUtc();
  final quoteDay = DateTime(utcDate.year, utcDate.month, utcDate.day);
  if (!quoteDay.isAfter(brokerDate)) return null;

  var delta = 0.0;
  for (var i = 0; i < holdings.length; i++) {
    final holding = holdings[i];
    final quote = quotes[i];
    if (!holding.shares.isFinite ||
        !quote.priceUsd.isFinite ||
        quote.priceUsd <= 0) return null;
    final anchorPrices = holding.closesUsd.entries
        .where(
          (entry) =>
              !entry.key.isAfter(brokerDate) &&
              brokerDate.difference(entry.key).inDays <= 4 &&
              entry.value.isFinite &&
              entry.value > 0,
        )
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (anchorPrices.isEmpty) return null;
    delta += holding.shares * (quote.priceUsd - anchorPrices.last.value);
  }
  final value = brokerNavUsd + delta;
  return value.isFinite && value > 0
      ? ProvisionalPortfolioPoint(newest.toUtc(), value)
      : null;
}

ProvisionalPortfolioPoint? projectPortfolioSinceSnapshot({
  required DateTime snapshotAt,
  required double brokerNavUsd,
  required List<double> brokerMarketValuesUsd,
  required List<ProvisionalHolding> holdings,
  required List<ProvisionalQuote> quotes,
  required DateTime now,
}) {
  if (holdings.isEmpty ||
      holdings.length != quotes.length ||
      holdings.length != brokerMarketValuesUsd.length ||
      !brokerNavUsd.isFinite ||
      brokerNavUsd <= 0) return null;
  final newest = quotes.map((quote) => quote.observedAt).reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
  final oldest = quotes.map((quote) => quote.observedAt).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
  if (!oldest.isAfter(snapshotAt) ||
      newest.isAfter(now) ||
      now.difference(newest) > const Duration(minutes: 30) ||
      newest.difference(oldest) > const Duration(minutes: 30)) return null;
  var delta = 0.0;
  for (var i = 0; i < holdings.length; i++) {
    final brokerValue = brokerMarketValuesUsd[i];
    final holding = holdings[i];
    if (!brokerValue.isFinite ||
        !holding.shares.isFinite ||
        !quotes[i].priceUsd.isFinite ||
        quotes[i].priceUsd <= 0) {
      return null;
    }
    delta += holding.shares * quotes[i].priceUsd - brokerValue;
  }
  final value = brokerNavUsd + delta;
  return value.isFinite && value > 0 && delta.abs() > 0.000001
      ? ProvisionalPortfolioPoint(newest.toUtc(), value)
      : null;
}
