import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/portfolio_chart_scale.dart';

const _multiLineScrubIntervalForTest = Duration(milliseconds: 50);

void main() {
  Widget chart({
    double valueOffset = 0,
    bool pageMenu = false,
    bool showRollingAverage = false,
    int pointCount = 10,
    List<MarketLineChartSeries>? series,
    ValueChanged<int>? onTooltipIndex,
  }) =>
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Scaffold(
          body: DesktopContextMenu(
            actions:
                pageMenu ? [DesktopMenuAction('Refresh', () {})] : const [],
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 800,
                height: 300,
                child: MarketLineChart(
                  series: series ??
                      [
                        MarketLineChartSeries(
                          points: [
                            for (var i = 0; i < pointCount; i++)
                              MarketLineChartPoint(
                                i.toDouble(),
                                i + valueOffset,
                              ),
                          ],
                          color: Colors.blue,
                        ),
                      ],
                  xLabels: List.generate(pointCount, (i) => 'Day $i'),
                  pointCount: pointCount,
                  yLabelFormatter: (value) => value.toStringAsFixed(1),
                  tooltipRowLabel: (mark) {
                    onTooltipIndex?.call(mark.index);
                    return 'Column ${mark.index}';
                  },
                  showRollingAverage: showRollingAverage,
                  curveLines: false,
                  curveSmoothness: 0,
                ),
              ),
            ),
          ),
        ),
      );

  ChartScene scene(WidgetTester tester) {
    final canvas = tester.widget<ChartCanvas>(find.byType(ChartCanvas));
    return (canvas.renderer as InteractiveRenderer)
        .buildScene(const Size(800, 300));
  }

  Future<void> drag(
    WidgetTester tester,
    int first,
    int last, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final current = scene(tester);
    final start =
        current.marks.firstWhere((mark) => mark.index == first).center;
    final end = current.marks.firstWhere((mark) => mark.index == last).center;
    final gesture = await tester.startGesture(start, kind: kind);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('rolling average replaces plotted values and follows zoom',
      (tester) async {
    await tester.pumpWidget(chart(showRollingAverage: true));
    expect(scene(tester).marks, hasLength(10));
    expect(
      scene(tester).marks.map((mark) => mark.value),
      [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5],
    );

    await drag(tester, 2, 7);
    expect(scene(tester).marks.map((mark) => mark.index), [2, 3, 4, 5, 6, 7]);
    expect(
      scene(tester).marks.map((mark) => mark.value),
      [2, 2.5, 3, 3.5, 4, 4.5],
    );

    await tester.pumpWidget(chart());
    expect(scene(tester).marks.map((mark) => mark.value), [2, 3, 4, 5, 6, 7]);
  });

  testWidgets('rolling average uses only the latest 20 observations',
      (tester) async {
    await tester.pumpWidget(chart(showRollingAverage: true, pointCount: 25));
    expect(scene(tester).marks, hasLength(25));
    expect(scene(tester).marks[19].value, 9.5);
    expect(scene(tester).marks[20].value, 10.5);
    expect(scene(tester).marks.last.value, 14.5);
  });

  testWidgets('mouse drag zooms in either direction and preserves indices',
      (tester) async {
    await tester.pumpWidget(chart());
    await drag(tester, 7, 2);
    expect(scene(tester).marks.map((mark) => mark.index), [2, 3, 4, 5, 6, 7]);
    expect(scene(tester).marks.first.center.dx, 64);
    expect(scene(tester).marks.last.center.dx, 768);
    expect(scene(tester).scale!.minValue, greaterThan(1));
    expect(scene(tester).scale!.maxValue, lessThan(8));
    await drag(tester, 3, 5);
    expect(scene(tester).marks.map((mark) => mark.index), [3, 4, 5]);
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(scene(tester).marks, hasLength(10));
  });

  testWidgets('mouse zoom drag keeps tooltip tracking the drag column',
      (tester) async {
    final tooltipIndexes = <int>[];
    await tester.pumpWidget(chart(onTooltipIndex: tooltipIndexes.add));
    final current = scene(tester);
    final start = current.marks.firstWhere((mark) => mark.index == 2).center;
    final end = current.marks.firstWhere((mark) => mark.index == 7).center;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    tooltipIndexes.clear();
    await gesture.moveTo(end);
    await tester.pump();

    expect(tooltipIndexes, contains(7));
    await gesture.up();
    await tester.pump();
    expect(scene(tester).marks.map((mark) => mark.index), [2, 3, 4, 5, 6, 7]);
  });

  testWidgets('multi-line long-press scrub coalesces rapid tooltip updates',
      (tester) async {
    final tooltipIndexes = <int>[];
    final lines = [
      for (var line = 0; line < 2; line++)
        MarketLineChartSeries(
          color: line == 0 ? Colors.blue : Colors.red,
          points: [
            for (var i = 0; i < 10; i++)
              MarketLineChartPoint(i.toDouble(), i + line.toDouble()),
          ],
        ),
    ];
    await tester.pumpWidget(
      chart(series: lines, onTooltipIndex: tooltipIndexes.add),
    );
    final current = scene(tester);
    final start = current.marks.firstWhere((mark) => mark.index == 2).center;
    final middle = current.marks.firstWhere((mark) => mark.index == 4).center;
    final end = current.marks.firstWhere((mark) => mark.index == 7).center;
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));

    tooltipIndexes.clear();
    await gesture.moveTo(middle);
    await tester.pump();
    expect(tooltipIndexes, contains(4));

    tooltipIndexes.clear();
    await gesture.moveTo(end);
    await tester.pump();
    expect(tooltipIndexes, isNot(contains(7)));

    await tester.pump(_multiLineScrubIntervalForTest);
    expect(tooltipIndexes, contains(7));
    await gesture.up();
    await tester.pump();
  });

  Future<void> rightClick(WidgetTester tester, Offset position) async {
    final gesture = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right click sets the start date and reset restores all points',
      (tester) async {
    await tester.pumpWidget(chart());
    await rightClick(tester, scene(tester).marks[3].center);
    expect(scene(tester).marks, hasLength(10));
    expect(find.text('Start from this date'), findsOneWidget);
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();
    expect(
      scene(tester).marks.map((mark) => mark.index),
      [3, 4, 5, 6, 7, 8, 9],
    );
    expect(scene(tester).marks.first.center.dx, 64);
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(scene(tester).marks, hasLength(10));
  });

  testWidgets('right click keeps the zoomed end date and ignores chart margins',
      (tester) async {
    await tester.pumpWidget(chart());
    await drag(tester, 2, 7);
    await rightClick(tester, scene(tester).marks[2].center);
    expect(scene(tester).marks.map((mark) => mark.index), [2, 3, 4, 5, 6, 7]);
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();
    expect(scene(tester).marks.map((mark) => mark.index), [4, 5, 6, 7]);
    await rightClick(tester, const Offset(20, 100));
    expect(find.text('Start from this date'), findsNothing);
    expect(scene(tester).marks.map((mark) => mark.index), [4, 5, 6, 7]);
    await rightClick(tester, scene(tester).marks.last.center);
    expect(scene(tester).marks.map((mark) => mark.index), [4, 5, 6, 7]);
  });

  testWidgets('dismissing the start date menu leaves the range unchanged',
      (tester) async {
    await tester.pumpWidget(chart());
    await rightClick(tester, scene(tester).marks[3].center);
    await tester.tapAt(const Offset(20, 280));
    await tester.pumpAndSettle();
    expect(find.text('Start from this date'), findsNothing);
    expect(scene(tester).marks, hasLength(10));
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });

  testWidgets(
      'chart menu wins over refresh menu even after holding right click',
      (tester) async {
    await tester.pumpWidget(chart(pageMenu: true));
    final gesture = await tester.startGesture(
      scene(tester).marks[3].center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Start from this date'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Start from this date'), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();
    expect(scene(tester).marks, hasLength(7));
    expect(find.text('Refresh'), findsNothing);
    await rightClick(tester, const Offset(400, 400));
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('start date rebases comparison lines like a shorter period',
      (tester) async {
    final rawValues = <List<double>>[
      [100.0, 200, 746.5, 754, 761.5, 769, 776.5, 784, 791.5, 799],
      [10000.0, 10050, 10100, 10201, 10302, 10403, 10504, 10605, 10706, 10807],
    ];
    final lines = [
      for (var line = 0; line < rawValues.length; line++)
        MarketLineChartSeries(
          color: line == 0 ? Colors.blue : Colors.red,
          points: [
            for (var i = 0; i < 10; i++)
              MarketLineChartPoint(
                i.toDouble(),
                scalePortfolioSeriesForComparison(rawValues[line])[i],
                comparisonValue: rawValues[line][i],
              ),
          ],
        ),
    ];
    await tester.pumpWidget(chart(series: lines));
    expect(scene(tester).scale!.maxValue, greaterThan(646.5));
    await rightClick(tester, scene(tester).marks[2].center);
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();
    for (var line = 0; line < rawValues.length; line++) {
      final expected =
          scalePortfolioSeriesForComparison(rawValues[line].skip(2));
      final marks = scene(tester)
          .marks
          .where((mark) => mark.seriesIndex == line)
          .toList();
      expect(marks.first.value, 0);
      for (var i = 0; i < marks.length; i++) {
        expect(marks[i].value, closeTo(expected[i], 1e-9));
        expect(marks[i].index, i + 2);
      }
    }
    expect(scene(tester).scale!.maxValue, lessThan(10));
    await drag(tester, 4, 7);
    for (var line = 0; line < rawValues.length; line++) {
      final expected = scalePortfolioSeriesForComparison(
        rawValues[line].sublist(4, 8),
      );
      final marks = scene(tester)
          .marks
          .where((mark) => mark.seriesIndex == line)
          .toList();
      for (var i = 0; i < marks.length; i++) {
        expect(marks[i].value, closeTo(expected[i], 1e-9));
      }
    }
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(scene(tester).scale!.maxValue, greaterThan(646.5));
  });

  testWidgets('clicks and touch drags keep the full range', (tester) async {
    await tester.pumpWidget(chart());
    await drag(tester, 3, 3);
    expect(find.byTooltip('Reset zoom'), findsNothing);
    await drag(tester, 2, 7, kind: PointerDeviceKind.touch);
    expect(scene(tester).marks, hasLength(10));
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });

  testWidgets('zoom survives rebuilds and resets when chart data changes',
      (tester) async {
    await tester.pumpWidget(chart());
    await drag(tester, 2, 7);
    await tester.pumpWidget(chart());
    expect(scene(tester).marks, hasLength(6));
    await tester.pumpWidget(chart(valueOffset: 100));
    expect(scene(tester).marks, hasLength(10));
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });
}
