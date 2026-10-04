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
}
