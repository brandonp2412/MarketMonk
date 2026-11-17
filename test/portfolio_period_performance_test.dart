import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/portfolio_period_performance.dart';

void main() {
  final start = DateTime(2026, 8, 17);
  final end = DateTime(2026, 11, 17);

  test('percent and dollar gain share the same investment result', () {
    final result = portfolioPeriodPerformance(
      startingValue: 300000,
      endingValue: 340000,
      startDate: start,
      endDate: end,
      cashFlows: {end: 100000},
    )!;
    expect(result.gain, -60000);
    expect(result.basis, 400000);
    expect(result.percent, -15);
  });

  test('deposits and withdrawals count towards net capital invested', () {
    final mid = start.add(Duration(days: end.difference(start).inDays ~/ 2));
    final result = portfolioPeriodPerformance(
      startingValue: 1000,
      endingValue: 1170,
      startDate: start,
      endDate: end,
      cashFlows: {mid: 200, end: -50},
    )!;
    expect(result.gain, 20);
    expect(result.basis, 1150);
    expect(result.percent, closeTo(20 / 1150 * 100, 1e-9));
  });

  test('cash-out gain from the screenshot determines both percentages', () {
    final accounts = [
      (value: 285164.50, gain: -4607.81, percentage: -1.59),
      (value: 23561.25, gain: 222.41, percentage: 0.95),
    ];
    for (final account in accounts) {
      final result = portfolioPeriodPerformance(
        startingValue: account.value - account.gain,
        endingValue: account.value,
        startDate: start,
        endDate: end,
        cashFlows: const {},
      )!;
      expect(result.gain, closeTo(account.gain, 0.001));
      expect(result.basis, closeTo(account.value - account.gain, 0.001));
      expect(result.percent, closeTo(account.percentage, 0.005));
    }
  });

  test('net investment basis remains unchanged regardless of flow dates', () {
    final early = start.add(const Duration(days: 1));
    final late = end.subtract(const Duration(days: 1));
    for (final date in [early, late]) {
      final result = portfolioPeriodPerformance(
        startingValue: 1000,
        endingValue: 1200,
        startDate: start,
        endDate: end,
        cashFlows: {date: 100},
      )!;
      expect(result.gain, 100);
      expect(result.percent, closeTo(100 / 1100 * 100, 1e-9));
    }
  });

  test('ignores flows outside the selected period', () {
    final result = portfolioPeriodPerformance(
      startingValue: 1000,
      endingValue: 900,
      startDate: start,
      endDate: end,
      cashFlows: {
        start: 100,
        start.subtract(const Duration(days: 1)): 300,
        end.add(const Duration(days: 1)): 200,
      },
    )!;
    expect(result.gain, -100);
    expect(result.percent, -10);
  });

  test('missing positive capital basis does not fabricate a return', () {
    expect(
      portfolioPeriodPerformance(
        startingValue: 0,
        endingValue: 500,
        startDate: start,
        endDate: end,
        cashFlows: const {},
      ),
      isNull,
    );
    expect(
      portfolioPeriodPerformance(
        startingValue: 1000,
        endingValue: 1000,
        startDate: end,
        endDate: end,
        cashFlows: const {},
      ),
      isNull,
    );
  });
}
