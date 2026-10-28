import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/provisional_portfolio.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  testWidgets('custom start clears period selection and survives line toggles',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'chartPeriodYears': 0,
      'chartPeriodMonths': 2,
      'chartPeriodDays': 0,
    });
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.addAccount('Second');
    for (final account in accounts.accounts) {
      await accounts.setIbkrConfig(
        account,
        IbkrAccountConfig(
          enabled: true,
          baseUrl: 'https://$account.example.test',
          token: 'test-token',
        ),
      );
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = [
      for (final days in [50, 40, 30, 20, 10, 1])
        today.subtract(Duration(days: days)),
    ];
    for (var i = 0; i < dates.length; i++) {
      while (dates[i].weekday == DateTime.saturday ||
          dates[i].weekday == DateTime.sunday) {
        dates[i] = dates[i].subtract(const Duration(days: 1));
      }
    }
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
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: ChartsPage(
              ibkrLoader: (config) async => IbkrPortfolioSnapshot(
                account: config.baseUrl,
                positions: const [],
                summary: const {
                  'netliquidation': {'value': 800.0, 'currency': 'USD'},
                },
                ledger: const {},
              ),
              ibkrPerformanceLoader: (config, period) async =>
                  IbkrPerformanceSeries(
                period: period,
                measure: 'TWR',
                currency: 'USD',
                startDate: dates.first,
                startNav: 100,
                dates: config.baseUrl.contains('Second')
                    ? [dates[1], ...dates.skip(3)]
                    : dates.skip(1).toList(),
                nav: config.baseUrl.contains('Second')
                    ? const [101, 103, 104, 105]
                    : const [200, 700, 746.5, 754, 761.5],
                returnDates: dates,
                returns: const [0, 0.01, 0.02, 0.03, 0.04, 0.05],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ChartScene scene() {
      final canvas = tester.widget<ChartCanvas>(find.byType(ChartCanvas));
      return (canvas.renderer as InteractiveRenderer)
          .buildScene(tester.getSize(find.byType(ChartCanvas)));
    }

    double periodBorderWidth() {
      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byKey(const Key('chart-period-2m')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return ((container.decoration! as BoxDecoration).border! as Border)
          .top
          .width;
    }

    expect(periodBorderWidth(), 2);
    final chartOrigin = tester.getTopLeft(find.byType(ChartCanvas));
    final mark = scene().marks.firstWhere((mark) => mark.index == 3);
    final mouse = await tester.startGesture(
      chartOrigin +
          Offset(
            mark.center.dx,
            scene().bounds!.top + scene().bounds!.height / 2,
          ),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();
    expect(periodBorderWidth(), 1);
    expect(scene().marks.map((mark) => mark.index).toSet(), {3, 4, 5});
    for (final line in [0, 1]) {
      expect(
        scene().marks.firstWhere((mark) => mark.seriesIndex == line).value,
        0,
      );
    }
    expect(scene().scale!.maxValue, lessThan(3));

    await tester.tap(find.byKey(const Key('chart-account-selector-Default')));
    await tester.pumpAndSettle();
    expect(scene().marks.map((mark) => mark.index).toSet(), {2, 3, 4});
    expect(periodBorderWidth(), 1);
    await tester.tap(find.byKey(const Key('chart-account-selector-Default')));
    await tester.pumpAndSettle();
    expect(scene().marks.map((mark) => mark.index).toSet(), {3, 4, 5});
    for (final line in [0, 1]) {
      expect(
        scene().marks.firstWhere((mark) => mark.seriesIndex == line).value,
        0,
      );
    }
    await tester.tap(find.byKey(const Key('chart-account-selector-Default')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-account-selector-Second')));
    await tester.pumpAndSettle();
    expect(find.byType(ChartCanvas), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(scene().marks.map((mark) => mark.index).toSet(), {3, 4, 5});
    expect(periodBorderWidth(), 1);
    await tester.tap(find.byKey(const Key('chart-period-2m')));
    await tester.pumpAndSettle();
    expect(periodBorderWidth(), 2);
    expect(find.byTooltip('Reset zoom'), findsNothing);
    expect(scene().marks.map((mark) => mark.index).toSet(), {0, 1, 2, 3, 4, 5});
  });

  testWidgets('broker returns and favorite returns rebase together after zoom',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'chartPeriodYears': 0,
      'chartPeriodMonths': 2,
      'chartPeriodDays': 0,
      'favoriteStocks': ['SPY'],
    });
    cacheSymbolMeta('SPY', 'USD');
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
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = [
      for (final days in [50, 40, 30, 20, 10, 1])
        today.subtract(Duration(days: days)),
    ];
    for (var i = 0; i < dates.length; i++) {
      while (dates[i].weekday == DateTime.saturday ||
          dates[i].weekday == DateTime.sunday) {
        dates[i] = dates[i].subtract(const Duration(days: 1));
      }
    }
    for (var i = 0; i < dates.length; i++) {
      await seedTestCandle(
        'SPY',
        usSessionDisplayDay(dates[i]),
        <double>[100, 110, 110, 115, 117, 120][i],
      );
    }
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
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: ChartsPage(
              ibkrLoader: (_) async => const IbkrPortfolioSnapshot(
                account: 'Default',
                positions: [],
                summary: {
                  'netliquidation': {'value': 1560.0, 'currency': 'USD'},
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
                nav: const [1010, 1515, 1530, 1545, 1560],
                cashFlows: const [0, 500, 0, 0, 0],
                returnDates: dates,
                returns: const [0, 0.01, 0.03, 0.02, 0.06, 0.04],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+4.00%'), findsOneWidget);
    expect(find.text('+20.00%'), findsOneWidget);
    await tester.tap(find.text('SPY'));
    await tester.pumpAndSettle();

    ChartScene scene() {
      final canvas = tester.widget<ChartCanvas>(find.byType(ChartCanvas));
      return (canvas.renderer as InteractiveRenderer)
          .buildScene(tester.getSize(find.byType(ChartCanvas)));
    }

    final orderedChart =
        tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(
      orderedChart.series.map((series) => series.name),
      ['SPY', 'Default'],
    );

    final accountBefore =
        scene().marks.where((mark) => mark.seriesIndex == 1).toList();
    expect(accountBefore.last.value, closeTo(4, 1e-9));

    final origin = tester.getTopLeft(find.byType(ChartCanvas));
    final selectedMark = scene().marks.firstWhere((mark) => mark.index == 3);
    final mouse = await tester.startGesture(
      origin +
          Offset(
            selectedMark.center.dx,
            scene().bounds!.top + scene().bounds!.height / 2,
          ),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start from this date'));
    await tester.pumpAndSettle();

    expect(find.text('+1.96%'), findsOneWidget);
    expect(find.text('+4.35%'), findsOneWidget);
    expect(find.text('+4.00%'), findsNothing);
    expect(find.text('+20.00%'), findsNothing);
    final account =
        scene().marks.where((mark) => mark.seriesIndex == 1).toList();
    final benchmark =
        scene().marks.where((mark) => mark.seriesIndex == 0).toList();
    expect(account.first.value, closeTo(0, 1e-9));
    expect(account.last.value, closeTo((1.04 / 1.02 - 1) * 100, 1e-9));
    expect(benchmark.first.value, closeTo(0, 1e-9));
    expect(benchmark.last.value, closeTo((120 / 115 - 1) * 100, 1e-9));
    final chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.tooltipRowLabel(account.last), contains('+1.96%'));
    expect(chart.tooltipRowLabel(benchmark.last), contains('+4.35%'));
  });
}
