import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/portfolio_returns.dart';

void main() {
  final cutoff = DateTime(2026, 1, 2);
  final history = IbkrPerformanceSeries(
    period: '1Y',
    measure: 'TWR',
    currency: 'USD',
    startDate: DateTime(2026),
    startNav: 0,
    dates: [DateTime(2026, 1, 1), cutoff, DateTime(2026, 1, 3)],
    nav: const [100, 110, 242],
    returnDates: [DateTime(2026, 1, 1), cutoff, DateTime(2026, 1, 3)],
    returns: const [0, .1, .21],
  );

  test('period gain excludes additional contributions', () {
    final result = accountPeriodReturn(history, 242, cutoff)!;
    expect(result.basis, closeTo(220, 1e-6));
    expect(result.gain, closeTo(22, 1e-6));
    expect(result.percent, closeTo(10, 1e-6));
  });

  test('missing period coverage is unavailable', () {
    expect(accountPeriodReturn(history, 242, DateTime(2025)), isNull);
  });

  test('historical account value chooses the latest fresh NAV', () {
    expect(accountNetAssetValueAt(history, cutoff), 110);
    expect(accountNetAssetValueAt(history, DateTime(2026, 1, 2, 12)), 110);
    expect(accountNetAssetValueAt(history, DateTime(2025, 12, 31)), isNull);
    expect(accountNetAssetValueAt(history, DateTime(2026, 1, 11)), isNull);
  });

  test('historical account value rejects invalid NAV', () {
    final invalid = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: cutoff,
      startNav: 0,
      dates: [cutoff],
      nav: const [double.nan],
      returnDates: [cutoff],
      returns: const [0],
    );
    expect(accountNetAssetValueAt(invalid, cutoff), isNull);
  });

  test('holding baseline accounts for later purchases and partial sales', () {
    final result = openHoldingPeriodReturn(
      currentValue: 180,
      currentShares: 10,
      baselinePrice: 10,
      cutoff: cutoff,
      trades: [
        (date: DateTime(2025), quantity: 10, price: 5),
        (date: DateTime(2026, 1, 3), quantity: 10, price: 20),
        (date: DateTime(2026, 1, 4), quantity: -10, price: 30),
      ],
    )!;
    expect(result.basis, 150);
    expect(result.gain, 30);
    expect(result.percent, 20);
  });

  test('fortnightly picker advances by exactly 14 calendar days', () {
    final now = DateTime(2026, 11, 14, 19);
    final start = DateTime(2026, 9, 5); // 70 calendar days, across NZ DST.
    final periods = portfolioFortnightlyPeriods(now, start);
    expect(periods, [0, -2, -3, -4, -5, -6]);
    for (var index = 1; index < periods.length; index++) {
      expect(
        portfolioReturnCutoff(periods[index], now),
        DateTime(2026, 11, 14 - index * 14),
      );
    }
  });

  test('fortnightly picker stops at one year of available broker history', () {
    final now = DateTime(2026, 11, 14);
    final periods = portfolioFortnightlyPeriods(now, DateTime(2020));
    expect(periods.length, 27); // Now plus 26 fortnightly stops.
    expect(portfolioReturnCutoff(periods.last, now), DateTime(2025, 11, 15));
    expect(portfolioFortnightlyPeriods(now, DateTime(2026, 11, 4)), [0]);
  });

  test('incomplete holding trade history is unavailable', () {
    expect(
      openHoldingPeriodReturn(
        currentValue: 100,
        currentShares: 10,
        baselinePrice: 5,
        cutoff: cutoff,
        trades: [(date: DateTime(2025), quantity: 5, price: 5)],
      ),
      isNull,
    );
  });
}
