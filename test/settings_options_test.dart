import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:provider/provider.dart';
import 'package:market_monk/settings_state.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new settings keep old defaults and survive a new state', () async {
    await seedTestSqlite({});
    final settings = SettingsState();
    await settings.initialized;
    expect(settings.startPage, 0);
    expect(settings.showChartGridlines, isFalse);
    expect(settings.fillChartArea, isTrue);

    await settings.setStartPage(2);
    await settings.setShowChartGridlines(true);
    await settings.setFillChartArea(false);

    final reloaded = SettingsState();
    await reloaded.initialized;
    expect(reloaded.startPage, 2);
    expect(reloaded.showChartGridlines, isTrue);
    expect(reloaded.fillChartArea, isFalse);
  });

  testWidgets('saved chart style reaches the renderer', (tester) async {
    await seedTestSqlite({
      'showChartGridlines': true,
      'fillChartArea': false,
    });
    final settings = SettingsState();
    await settings.initialized;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: TickerLine(
                spots: const [
                  MarketLineChartPoint(0, 1),
                  MarketLineChartPoint(1, 2),
                ],
                dates: [DateTime(2026, 1, 1), DateTime(2026, 1, 2)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.showGridlines, isTrue);
    expect(chart.fillChartArea, isFalse);
  });

  test('invalid persisted start page falls back to Charts', () async {
    await seedTestSqlite({'startPage': 99});
    final settings = SettingsState();
    await settings.initialized;
    expect(settings.startPage, 0);
    await settings.setStartPage(-1);
    expect(settings.startPage, 0);
  });
}
