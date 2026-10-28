import 'sqlite_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TickerLine renders through Drafter with themed axes', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({});
    final dates = List.generate(10, (i) => DateTime(2026, 1, i + 1));
    final spots = [
      for (var i = 0; i < 10; i++)
        MarketLineChartPoint(i.toDouble(), 100.0 + i * 10, column: i),
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

    expect(find.byType(MarketLineChart), findsOneWidget);
    final chart = tester.widget<MarketLineChart>(
      find.byType(MarketLineChart),
    );
    expect(chart.series.single.points, hasLength(10));
    expect(chart.leftInset, 64);
    expect(chart.pointCount, 10);
  });

  testWidgets('intraday axis uses times while tooltips retain full dates', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({});
    final settings = SettingsState();
    await settings.initialized;
    addTearDown(settings.dispose);
    final dates = [
      DateTime(2026, 10, 27, 9, 30),
      DateTime(2026, 10, 27, 10, 15),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: TickerLine(
              intraday: true,
              dates: dates,
              spots: const [
                MarketLineChartPoint(0, 100),
                MarketLineChartPoint(1, 110),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final chart = tester.widget<MarketLineChart>(
      find.byType(MarketLineChart),
    );
    expect(chart.xLabels, ['09:30', '10:15']);
    final ticker = tester.widget<TickerLine>(find.byType(TickerLine));
    expect(
      ticker.tooltipTextAt(0, DateFormat('${settings.dateFormat} HH:mm')),
      contains('27/10/26 09:30'),
    );
  });

  test('x-axis selection keeps both ends and balances middle labels', () {
    final selected = MarketLineChart.selectXAxisLabelIndices(
      const [0, 20, 40, 60, 80, 100],
      const [18, 18, 18, 18, 18, 18],
      12,
    );
    expect(selected, orderedEquals([0, 3, 5]));
  });

  test('dense x axes measure labels based on width rather than history size', () {
    final candidates = MarketLineChart.xAxisLabelCandidates(10000, 960);
    expect(candidates.length, lessThanOrEqualTo(80));
    expect(candidates.first, 0);
    expect(candidates.last, 9999);
    expect(candidates.toSet(), hasLength(candidates.length));
    expect(
      MarketLineChart.xAxisLabelCandidates(6, 960),
      orderedEquals([0, 1, 2, 3, 4, 5]),
    );
    expect(MarketLineChart.xAxisLabelCandidates(0, 960), isEmpty);
    expect(MarketLineChart.xAxisLabelCandidates(1, 0), [0]);
    expect(MarketLineChart.xAxisLabelCandidates(10000, 0), [0, 9999]);
  });

  test('TickerLine tooltip shows price and date on the same line', () {
    final date = DateTime(2026, 1, 2);
    const spot = MarketLineChartPoint(0, 123.45, column: 0);
    final chart = TickerLine(dates: [date], spots: const [spot]);

    final tooltip = chart.tooltipTextAt(0, DateFormat('d/M/yy'));

    expect(tooltip, r'$123.45 · 2/1/26');
    expect(tooltip, isNot(contains('\n')));
  });
}
