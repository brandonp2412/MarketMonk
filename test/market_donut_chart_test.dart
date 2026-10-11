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
}
