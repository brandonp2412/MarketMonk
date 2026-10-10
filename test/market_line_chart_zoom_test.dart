import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_line_chart.dart';

void main() {
  Widget chart({double valueOffset = 0}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 300,
            child: MarketLineChart(
              series: [
                MarketLineChartSeries(
                  points: [
                    for (var i = 0; i < 10; i++)
                      MarketLineChartPoint(i.toDouble(), i + valueOffset),
                  ],
                  color: Colors.blue,
                ),
              ],
              xLabels: List.generate(10, (i) => 'Day $i'),
              pointCount: 10,
              yLabelFormatter: (value) => value.toStringAsFixed(1),
              tooltipRowLabel: (mark) => 'Column ${mark.index}',
              curveLines: false,
              curveSmoothness: 0,
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
