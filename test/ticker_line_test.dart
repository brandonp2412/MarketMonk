import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
