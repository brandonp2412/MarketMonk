import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';

void main() {
  test('infers real contributions from NAV and cumulative TWR', () {
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'NZD',
      startDate: DateTime(2026, 1, 1),
      startNav: 0,
      dates: [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
      ],
      nav: const [3355.69, 3355.196063, 23326.951487],
      cashFlows: const [0, 0, 0],
      returnDates: [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
      ],
      returns: const [0, -0.00014719, -0.00063536],
    );

    final pnl = calculateIbkrCashOutPnl(
      performance,
      const IbkrAccountValue(value: 24278.20, currency: 'NZD'),
    );

    expect(pnl.netContributions, closeTo(23338.84018, 0.01));
    expect(pnl.profitLoss, closeTo(939.35982, 0.01));
    expect(pnl.percent, closeTo(4.0249, 0.001));
  });

  test('historical profit is cumulative as of the selected date', () {
    const contributions = 23338.84;
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: DateTime(2026, 8, 1),
      startNav: 0,
      dates: [
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
        DateTime(2026, 11, 3),
      ],
      nav: const [contributions, 23908.04, 24039.24],
      returnDates: [
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
        DateTime(2026, 11, 3),
      ],
      returns: const [0, 569.20 / contributions, 700.40 / contributions],
    );
    final then = calculateIbkrCashOutPnlAt(performance, DateTime(2026, 9, 1))!;
    final now = calculateIbkrCashOutPnlAt(performance, DateTime(2026, 11, 3))!;
    expect(then.netContributions, closeTo(contributions, 0.01));
    expect(then.profitLoss, closeTo(569.20, 0.01));
    expect(now.profitLoss, closeTo(700.40, 0.01));
    expect(now.currentValue - then.currentValue, closeTo(131.20, 0.01));
    expect(
      calculateIbkrCashOutPnlAt(performance, DateTime(2026, 10, 1)),
      isNull,
    );
  });

  test('withdrawals reduce net contributions', () {
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'NZD',
      startDate: DateTime(2026, 1, 1),
      startNav: 0,
      dates: [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
      ],
      nav: const [1000, 1100, 900],
      cashFlows: const [0, 0, 0],
      returnDates: [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
      ],
      returns: const [0, 0.1, 0.1],
    );

    final pnl = calculateIbkrCashOutPnl(
      performance,
      const IbkrAccountValue(value: 950, currency: 'NZD'),
    );

    expect(pnl.netContributions, closeTo(800, 0.000001));
    expect(pnl.profitLoss, closeTo(150, 0.000001));
    final beforeWithdrawal = calculateIbkrCashOutPnlAt(
      performance,
      DateTime(2026, 1, 3),
    )!;
    expect(beforeWithdrawal.netContributions, closeTo(1000, 0.000001));
    expect(beforeWithdrawal.profitLoss, closeTo(100, 0.000001));
  });

  test('requires history from account inception', () {
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'NZD',
      startDate: DateTime(2025, 10, 1),
      startNav: 300000,
      dates: [DateTime(2026, 9, 30)],
      nav: const [333989.91],
      cashFlows: const [0],
      returnDates: [DateTime(2026, 9, 30)],
      returns: const [0.1169],
    );

    expect(
      () => calculateIbkrCashOutPnl(
        performance,
        const IbkrAccountValue(value: 340000, currency: 'NZD'),
      ),
      throwsStateError,
    );
  });
}
