import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/provisional_portfolio.dart';

void main() {
  test('extends broker NAV using dated closes, including negative shares', () {
    final points = projectPortfolioFromCloses(
      brokerDate: DateTime(2026, 10, 15),
      brokerNavUsd: 10000,
      latestDate: DateTime(2026, 10, 19),
      holdings: [
        ProvisionalHolding(
          shares: 10,
          closesUsd: {
            DateTime(2026, 10, 15): 100,
            DateTime(2026, 10, 16): 105,
            DateTime(2026, 10, 19): 103,
          },
        ),
        ProvisionalHolding(
          shares: -5,
          closesUsd: {
            DateTime(2026, 10, 15): 50,
            DateTime(2026, 10, 16): 48,
            DateTime(2026, 10, 19): 51,
          },
        ),
      ],
    );
    expect(points.map((point) => point.date).toList(), [
      DateTime(2026, 10, 16),
      DateTime(2026, 10, 19),
    ]);
    expect(points.map((point) => point.valueUsd).toList(), [10060, 10025]);
  });

  test('requires every holding to have a recent anchor and price', () {
    final points = projectPortfolioFromCloses(
      brokerDate: DateTime(2026, 10, 15),
      brokerNavUsd: 10000,
      latestDate: DateTime(2026, 10, 19),
      holdings: [
        ProvisionalHolding(
          shares: 10,
          closesUsd: {
            DateTime(2026, 10, 8): 100,
            DateTime(2026, 10, 16): 105,
          },
        ),
      ],
    );
    expect(points, isEmpty);
  });

  test('holds quiet-market close but does not carry old quotes indefinitely',
      () {
    final points = projectPortfolioFromCloses(
      brokerDate: DateTime(2026, 10, 15),
      brokerNavUsd: 10000,
      latestDate: DateTime(2026, 10, 24),
      holdings: [
        ProvisionalHolding(
          shares: 10,
          closesUsd: {
            DateTime(2026, 10, 15): 100,
            DateTime(2026, 10, 16): 110,
            DateTime(2026, 10, 23): 120,
          },
        ),
        ProvisionalHolding(
          shares: 5,
          closesUsd: {
            DateTime(2026, 10, 15): 20,
            DateTime(2026, 10, 16): 22,
          },
        ),
      ],
    );
    expect(points, hasLength(1));
    expect(points.single.valueUsd, 10110);
  });

  test('live quote extends last broker value during a newer session', () {
    final observed = DateTime.utc(2026, 10, 19, 15);
    final estimate = projectPortfolioFromQuotes(
      brokerDate: DateTime(2026, 10, 16),
      brokerNavUsd: 10000,
      now: observed.add(const Duration(minutes: 1)),
      holdings: [
        ProvisionalHolding(
          shares: 10,
          closesUsd: {
            DateTime(2026, 10, 16): 100,
          },
        ),
        ProvisionalHolding(
          shares: 5,
          closesUsd: {
            DateTime(2026, 10, 16): 20,
          },
        ),
      ],
      quotes: [
        ProvisionalQuote(observedAt: observed, priceUsd: 105),
        ProvisionalQuote(observedAt: observed, priceUsd: 21),
      ],
    );
    expect(estimate?.valueUsd, 10055);
    expect(estimate?.date, observed.toLocal());
  });

  test('does not project older or widely mismatched intraday quotes', () {
    final observed = DateTime.utc(2026, 10, 19, 15);
    ProvisionalPortfolioPoint? projection(DateTime second, DateTime now) =>
        projectPortfolioFromQuotes(
          brokerDate: DateTime(2026, 10, 16),
          brokerNavUsd: 10000,
          now: now,
          holdings: [
            ProvisionalHolding(
              shares: 1,
              closesUsd: {
                DateTime(2026, 10, 16): 100,
              },
            ),
            ProvisionalHolding(
              shares: 1,
              closesUsd: {
                DateTime(2026, 10, 16): 100,
              },
            ),
          ],
          quotes: [
            ProvisionalQuote(observedAt: observed, priceUsd: 101),
            ProvisionalQuote(observedAt: second, priceUsd: 101),
          ],
        );
    expect(
      projection(
        observed.subtract(const Duration(hours: 2)),
        observed.add(const Duration(minutes: 1)),
      ),
      isNull,
    );
    expect(
      projection(observed, observed.add(const Duration(days: 5))),
      isNull,
    );
  });

  test('same-session prices adjust a broker snapshot only after it was read',
      () {
    final snapshot = DateTime.utc(2026, 10, 19, 15, 00);
    final fresh = snapshot.add(const Duration(minutes: 7));
    final holding = ProvisionalHolding(
      shares: 10,
      closesUsd: {DateTime(2026, 10, 19): 100},
    );
    ProvisionalPortfolioPoint? result(DateTime quoteAt) =>
        projectPortfolioSinceSnapshot(
          snapshotAt: snapshot,
          brokerNavUsd: 10000,
          brokerMarketValuesUsd: [1000],
          holdings: [holding],
          quotes: [ProvisionalQuote(observedAt: quoteAt, priceUsd: 103)],
          now: fresh.add(const Duration(minutes: 1)),
        );
    expect(result(fresh)?.valueUsd, 10030);
    expect(result(snapshot), isNull);
    expect(result(snapshot.subtract(const Duration(minutes: 1))), isNull);
  });
}
