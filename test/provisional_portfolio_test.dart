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
}
