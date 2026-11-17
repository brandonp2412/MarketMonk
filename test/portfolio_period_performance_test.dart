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
    expect(result.basis, 300000);
    expect(result.percent, -20);
  });

  test('deposits and withdrawals affect the denominator by time invested', () {
    final mid = start.add(Duration(days: end.difference(start).inDays ~/ 2));
    final result = portfolioPeriodPerformance(
      startingValue: 1000,
      endingValue: 1170,
      startDate: start,
      endDate: end,
      cashFlows: {mid: 200, end: -50},
    )!;
    expect(result.gain, 20);
    expect(result.basis, closeTo(1100, 3));
    expect(result.percent, closeTo(20 / result.basis * 100, 0.000001));
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
