import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/provisional_portfolio.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  testWidgets(
      'portfolio and favorites share compact candle and average controls',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 940);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'favoriteStocks': ['SPY'],
      'chartPeriodYears': 0,
      'chartPeriodMonths': 2,
      'chartPeriodDays': 0,
    });
    cacheSymbolMeta('SPY', 'USD');
    final now = DateUtils.dateOnly(DateTime.now());
    final dates = [
      for (final days in [22, 18, 15, 12, 8, 5, 3])
        now.subtract(Duration(days: days)),
    ];
    for (var i = 0; i < dates.length; i++) {
      while (dates[i].weekday == DateTime.saturday ||
          dates[i].weekday == DateTime.sunday) {
        dates[i] = dates[i].subtract(const Duration(days: 1));
      }
      await seedTestCandle('SPY', usSessionDisplayDay(dates[i]), 110 + i * 3);
    }
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://example.test',
        token: 'test-token',
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                SettingsState(localCurrencyDetector: () async => 'USD'),
          ),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChartsPage(
              ibkrLoader: (_) async => const IbkrPortfolioSnapshot(
                account: 'Default',
                positions: [],
                summary: {
                  'netliquidation': {'value': 1100.0, 'currency': 'USD'},
                },
                ledger: {},
              ),
              ibkrPerformanceLoader: (_, period) async => IbkrPerformanceSeries(
                period: period,
                measure: 'TWR',
                currency: 'USD',
                startDate: dates.first,
                startNav: 1000,
                dates: dates.skip(1).toList(),
                nav: const [1005, 1020, 1015, 1040, 1080, 1100],
                returnDates: dates,
                returns: const [0, 0.005, 0.02, 0.015, 0.04, 0.08, 0.10],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-rolling-average')), findsNothing);
    expect(
      find.byKey(const Key('chart-portfolio-candle-toggle')),
      findsNothing,
    );
    final menu = find.byKey(const Key('chart-menu-button'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-menu-rolling-average')), findsOneWidget);
    expect(find.byKey(const Key('chart-menu-candles')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chart-menu-candles')));
    await tester.pumpAndSettle();
    var chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.showCandlesticks, true);
    expect(chart.candles, isNotEmpty);
    expect(chart.candles.every((bar) => bar.sampled), true);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-menu-rolling-average')));
    await tester.pumpAndSettle();
    chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.showRollingAverage, true);

    await tester.tap(find.text('SPY'));
    await tester.pumpAndSettle();
    chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.series, hasLength(2));
    expect(chart.candles.any((bar) => bar.sampled), true);
    expect(chart.candles.any((bar) => !bar.sampled), true);
    expect(chart.showCandlesticks, true);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    final average = find.byKey(const Key('chart-rolling-average'));
    final candles = find.byKey(const Key('chart-portfolio-candle-toggle'));
    final desktopControls =
        find.byKey(const Key('desktop-portfolio-chart-controls'));
    expect(desktopControls, findsOneWidget);
    expect(average, findsOneWidget);
    expect(candles, findsOneWidget);
    await tester.ensureVisible(desktopControls);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(desktopControls).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const Key('portfolio-summary-content')))
            .dy,
      ),
    );
  });
}
