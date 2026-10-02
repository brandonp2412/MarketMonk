import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('TickerLine shows currency labels on the Y axis', (
    WidgetTester tester,
  ) async {
    final dates = List.generate(10, (i) => DateTime(2026, 1, i + 1));
    final spots = [
      for (var i = 0; i < 10; i++) FlSpot(i.toDouble(), 100.0 + i * 10),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsState(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: TickerLine(dates: dates, spots: spots),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('\$'), findsWidgets);
  });

  testWidgets('TickerLine tooltip shows price and date on the same line', (
    WidgetTester tester,
  ) async {
    final date = DateTime(2026, 1, 2);
    const spot = FlSpot(0, 123.45);
    final chart = TickerLine(dates: [date], spots: const [spot]);
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    final bar = LineChartBarData(spots: const [spot]);
    final tooltip = chart.getTooltip(
      [LineBarSpot(bar, 0, spot)],
      context,
      DateFormat('d/M/yy'),
    ).single;

    expect(tooltip.text, r'$123.45 · 2/1/26');
    expect(tooltip.text, isNot(contains('\n')));
  });
}
