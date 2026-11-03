import 'dart:math' as math;

import 'package:drafter/painting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_donut_chart.dart';

void main() {
  testWidgets('uses pie section radius as ring thickness', (tester) async {
    int? selectedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 260,
              child: MarketDonutChart(
                slices: const [
                  MarketDonutSlice(
                    value: 1,
                    color: Colors.blue,
                    label: 'VOO',
                  ),
                ],
                selectedIndex: null,
                onSelectionChanged: (index) => selectedIndex = index,
                centerSpaceRadius: 55,
                radius: 75,
                selectedRadius: 90,
              ),
            ),
          ),
        ),
      ),
    );

    final chartCenter = tester.getCenter(find.byType(MarketDonutChart));
    await tester.tapAt(chartCenter + const Offset(0, -120));
    await tester.pump();

    expect(selectedIndex, 0);
  });

  testWidgets('mobile tap expands the donut slice smoothly', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 260,
              child: StatefulBuilder(
                builder: (context, setState) => MarketDonutChart(
                  slices: const [
                    MarketDonutSlice(
                      value: 1,
                      color: Colors.blue,
                      label: 'VOO',
                    ),
                  ],
                  selectedIndex: selectedIndex,
                  onSelectionChanged: (index) =>
                      setState(() => selectedIndex = index),
                  centerSpaceRadius: 55,
                  radius: 60,
                  selectedRadius: 75,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final animation = tester
        .widget<AnimatedBuilder>(
          find.descendant(
            of: find.byType(MarketDonutChart),
            matching: find.byType(AnimatedBuilder),
          ),
        )
        .animation as Animation<double>;
    final chartCenter = tester.getCenter(find.byType(MarketDonutChart));
    expect(animation.value, 1);

    await tester.tapAt(chartCenter + const Offset(0, -100));
    await tester.pump();
    expect(selectedIndex, 0);
    expect(animation.value, 0);
    await tester.pump(const Duration(milliseconds: 110));
    expect(animation.value, greaterThan(0));
    expect(animation.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(animation.value, 1);

    // The expanded ring's outer edge must remain tappable inside 260px.
    await tester.tapAt(chartCenter + const Offset(0, -120));
    await tester.pump();
    expect(selectedIndex, 0);
  });
  testWidgets('animates allocation changes and retargets in flight',
      (tester) async {
    var slices = const [
      MarketDonutSlice(value: 3, color: Colors.blue, label: 'VOO'),
      MarketDonutSlice(value: 1, color: Colors.red, label: 'MSFT'),
    ];
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 260,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return MarketDonutChart(
                    slices: slices,
                    selectedIndex: null,
                    onSelectionChanged: (_) {},
                    centerSpaceRadius: 55,
                    radius: 60,
                    selectedRadius: 75,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Map<String, ({double start, double sweep})> arcs() {
      final dynamic renderer =
          tester.widget<ChartCanvas>(find.byType(ChartCanvas)).renderer;
      return {
        for (final dynamic arc in renderer.arcs as List<dynamic>)
          arc.label as String: (
            start: arc.startAngle as double,
            sweep: arc.sweep as double,
          ),
      };
    }

    final before = arcs();
    expect(before['VOO']!.sweep, closeTo(math.pi * 1.5, 0.000001));
    update(() {
      slices = const [
        MarketDonutSlice(value: 1, color: Colors.blue, label: 'VOO'),
        MarketDonutSlice(value: 3, color: Colors.red, label: 'MSFT'),
      ];
    });
    await tester.pump();
    expect(arcs()['VOO']!.sweep, closeTo(before['VOO']!.sweep, 0.000001));

    await tester.pump(const Duration(milliseconds: 90));
    final halfway = arcs();
    expect(halfway['VOO']!.sweep, lessThan(before['VOO']!.sweep));
    expect(halfway['VOO']!.sweep, greaterThan(math.pi / 2));

    update(() {
      slices = const [
        MarketDonutSlice(value: 2, color: Colors.blue, label: 'VOO'),
        MarketDonutSlice(value: 2, color: Colors.red, label: 'MSFT'),
      ];
    });
    await tester.pump();
    expect(arcs()['VOO']!.sweep, closeTo(halfway['VOO']!.sweep, 0.000001));

    await tester.pumpAndSettle();
    final after = arcs();
    expect(after['VOO']!.sweep, closeTo(math.pi, 0.000001));

    final oldMsftStart = after['MSFT']!.start;
    update(() {
      slices = const [
        MarketDonutSlice(value: 3, color: Colors.red, label: 'MSFT'),
        MarketDonutSlice(value: 1, color: Colors.blue, label: 'VOO'),
      ];
    });
    await tester.pump();
    expect(arcs()['MSFT']!.start, closeTo(oldMsftStart, 0.000001));
    await tester.pump(const Duration(milliseconds: 90));
    expect(arcs()['MSFT']!.start, lessThan(oldMsftStart));
    await tester.pumpAndSettle();
    final reordered = arcs();
    expect(reordered['MSFT']!.start, closeTo(-math.pi / 2, 0.000001));
    expect(reordered['MSFT']!.sweep, closeTo(math.pi * 1.5, 0.000001));
  });
}
