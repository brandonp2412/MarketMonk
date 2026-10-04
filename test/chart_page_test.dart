import 'package:drafter/drafter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/portfolio_chart_scale.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';
import 'test_log_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('portfolio comparison scaling normalizes different account sizes', () {
    final large = scalePortfolioSeriesForComparison([100000, 110000]);
    final small = scalePortfolioSeriesForComparison([1000, 1200]);

    expect(large[0], closeTo(0, 1e-9));
    expect(large[1], closeTo(10, 1e-9));
    expect(small[0], closeTo(0, 1e-9));
    expect(small[1], closeTo(20, 1e-9));
  });

  testWidgets('inactive kept-alive charts do not fetch in background',
      (tester) async {
    await seedTestSqlite({});

    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'secret-token',
      ),
    );
    var portfolioLoads = 0;
    var performanceLoads = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChartsPage(
              isActive: false,
              ibkrLoader: (_) async {
                portfolioLoads++;
                throw StateError('inactive chart fetched portfolio');
              },
              ibkrPerformanceLoader: (_, __) async {
                performanceLoads++;
                throw StateError('inactive chart fetched performance');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(portfolioLoads, 0);
    expect(performanceLoads, 0);
  });

  // Regression test for issue #35: the chart page's first frame can be laid
  // out with degenerate constraints (e.g. before the Linux window reaches its
  // real size). The search-bar overlay height must be re-measured once the
  // window resizes, otherwise the time chips stay stuck under the search bar.
  testWidgets(
    'time chips stay below the search bar after a degenerate first frame',
    (WidgetTester tester) async {
      await seedTestSqlite({});
      final accounts = testAccountManager();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 30);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsState()),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pump();

      // The temporarily tiny layout must not build the search overlay and
      // therefore must not report a RenderFlex overflow.
      expect(tester.takeException(), null);

      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      await tester.pump();

      final searchBottom = tester.getBottomLeft(find.byType(SearchBar)).dy;
      final chipTop = tester.getTopLeft(find.text('5d')).dy;
      expect(chipTop, greaterThanOrEqualTo(searchBottom));

      // The scrollable leaves room for the floating navigation dock rather
      // than hiding its final rows.
      final listView = tester.widget<ListView>(find.byType(ListView).first);
      final padding = listView.padding! as EdgeInsets;
      expect(padding.bottom, greaterThan(92));
      expect(find.text('Refresh'), findsNothing);

      await tester.drag(find.byType(ListView).first, const Offset(0, 240));
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cached IBKR chart waits for the saved period before rendering',
    (WidgetTester tester) async {
      await seedTestSqlite({
        'ibkrAccountConfigs':
            '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
        'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
        'chartPeriodYears': 0,
        'chartPeriodMonths': 0,
        'chartPeriodDays': 5,
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final accounts = testAccountManager();
      await accounts.init();
      await accounts.cachePortfolio(
        'Default',
        [
          Position(
            symbol: 'VOO',
            name: 'VANGUARD S&P 500 ETF',
            nativeCurrency: 'USD',
            netShares: 10,
            avgCost: 500,
            currentPrice: 550,
            firstBuyDate: DateTime(2025),
            lastBuyDate: DateTime(2026),
          ),
        ],
        const IbkrAccountValue(value: 10000, currency: 'NZD'),
        netLiquidationUsd: 5750,
      );
      await accounts.cacheIbkrPerformance(
        'Default',
        IbkrPerformanceSeries(
          period: '1Y',
          measure: 'TWR',
          currency: 'NZD',
          startDate: DateTime(2025, 10, 1),
          startNav: 9000,
          dates: [
            DateTime(2026, 9, 21),
            DateTime(2026, 9, 22),
            DateTime(2026, 9, 23),
            DateTime(2026, 9, 24),
            DateTime(2026, 9, 25),
            DateTime(2026, 9, 26),
            DateTime(2026, 9, 27),
            DateTime(2026, 9, 28),
            DateTime(2026, 9, 29),
            DateTime(2026, 9, 30),
          ],
          nav: const [
            9100,
            9200,
            9300,
            9400,
            9500,
            9600,
            9700,
            9800,
            9900,
            10000,
          ],
          returnDates: [
            DateTime(2025, 10, 1),
            DateTime(2026, 9, 30),
          ],
          returns: const [0, 0.1111],
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsState()),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ChartsPage(
                ibkrLoader: (_) async =>
                    throw StateError('fresh portfolio fetch should not block'),
                ibkrPerformanceLoader: (config, period) async =>
                    throw StateError(
                  'fresh performance fetch should not block',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MarketLineChart), findsNothing);
      expect(find.bySemanticsLabel('Loading portfolio'), findsOneWidget);

      await tester.pump();

      final chart = tester.widget<MarketLineChart>(
        find.byType(MarketLineChart),
      );
      final cachedSpots = chart.series.single.points;
      expect(cachedSpots, hasLength(5));
      expect(cachedSpots.first.y, closeTo(9400 / (10000 / 5750), 1e-6));
      expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);

      final lastSpot = cachedSpots.last;
      final tooltip = chart.tooltipRowLabel(
        PlotMark(
          index: lastSpot.column!,
          seriesIndex: 0,
          seriesName: chart.series.single.name,
          label: '',
          value: lastSpot.y,
          center: Offset.zero,
          region: Rect.zero,
          color: chart.series.single.color,
        ),
      );
      expect(
        tooltip,
        matches(RegExp(r'^\$[\d,.]+ · \d{1,2}/\d{1,2}/\d{2}$')),
      );
      expect(tooltip, isNot(contains('\n')));

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'IBKR chart does not synthesize a current-day point from live NAV',
    (WidgetTester tester) async {
      await seedTestSqlite({
        'ibkrAccountConfigs':
            '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
        'chartPeriodYears': 0,
        'chartPeriodMonths': 0,
        'chartPeriodDays': 5,
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        allRatesFromUsd.remove('NZD');
      });

      allRatesFromUsd['NZD'] = 1.7;
      final accounts = testAccountManager();
      await accounts.init();
      final historyStart = DateTime(2026, 9, 23);
      await accounts.cachePortfolio(
        'Default',
        [
          Position(
            symbol: 'VOO',
            name: 'VANGUARD S&P 500 ETF',
            nativeCurrency: 'USD',
            netShares: 10,
            avgCost: 500,
            currentPrice: 550,
            firstBuyDate: DateTime(2025),
            lastBuyDate: DateTime(2026),
          ),
        ],
        const IbkrAccountValue(value: 10000, currency: 'NZD'),
      );
      await accounts.cacheIbkrPerformance(
        'Default',
        IbkrPerformanceSeries(
          period: '1Y',
          measure: 'TWR',
          currency: 'NZD',
          startDate: historyStart,
          startNav: 9000,
          dates: [DateTime(2026, 9, 24), DateTime(2026, 9, 25)],
          nav: const [9200, 9500],
          returnDates: [historyStart, DateTime(2026, 9, 25)],
          returns: const [0, 0.05],
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsState()),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ChartsPage()),
          ),
        ),
      );
      await tester.pump();

      final chart =
          tester.widget<MarketLineChart>(find.byType(MarketLineChart));
      final spots = chart.series.single.points;
      expect(spots, hasLength(3));
      expect(spots.last.y, closeTo(9500 / 1.7, 1e-6));

      await tester.pumpAndSettle();
    },
  );

  testWidgets('IBKR chart retries broker history without synthetic fallback', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({
      'ibkrAccountConfigs':
          '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
      'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
      'displayCurrency': 'NZD',
      'visibleCurrencies': ['NZD'],
      'exchangeRate_NZD': 1.7,
    });
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = testAccountManager();
    await accounts.init();
    final cachedPosition = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition],
      const IbkrAccountValue(value: 10000, currency: 'NZD'),
      netLiquidationUsd: 5750,
    );
    final now = DateTime.now();
    await seedTestCandle(
      'VOO',
      DateTime(now.year, now.month, now.day - 20),
      500,
    );
    await seedTestCandle(
      'VOO',
      DateTime(now.year, now.month, now.day),
      550,
    );

    var ibkrLoads = 0;
    Future<IbkrPortfolioSnapshot> loader(IbkrAccountConfig _) async {
      ibkrLoads++;
      return const IbkrPortfolioSnapshot(
        account: '****6552',
        positions: [
          IbkrPosition(
            symbol: 'VOO',
            securityType: 'STK',
            currency: 'USD',
            exchange: 'ARCA',
            conid: 1,
            quantity: 10,
            marketPrice: 550,
            marketValue: 5500,
            averageCost: 500,
            unrealizedPnl: 500,
            realizedPnl: 0,
          ),
        ],
        summary: {
          'netliquidation': {'value': 10100, 'currency': 'NZD'},
          'netliquidationbycurrency:usd': {'value': 5800, 'currency': 'USD'},
        },
        ledger: {},
      );
    }

    silenceTalkerForTest();
    var performanceLoads = 0;
    var performanceAvailable = false;
    Future<IbkrPerformanceSeries> performanceLoader(
      IbkrAccountConfig _,
      String period,
    ) async {
      performanceLoads++;
      expectSync(period, '1Y');
      if (!performanceAvailable) {
        throw StateError('reporting temporarily unavailable');
      }
      return IbkrPerformanceSeries(
        period: period,
        measure: 'TWR',
        currency: 'NZD',
        startDate: DateTime(2025, 9, 30),
        startNav: 300000,
        dates: [DateTime(2026, 9, 29)],
        nav: const [333989.91],
        returnDates: [DateTime(2025, 9, 30), DateTime(2026, 9, 29)],
        returns: const [0, 0.1169],
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChartsPage(
              ibkrLoader: loader,
              ibkrPerformanceLoader: performanceLoader,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(ibkrLoads, 0);
    expect(find.textContaining('10,000'), findsWidgets);
    expect(allRatesFromUsd['NZD'], closeTo(10000 / 5750, 1e-9));
    final failedPerformanceLoads = performanceLoads;
    expect(failedPerformanceLoads, greaterThan(0));
    expect(find.text('History unavailable'), findsOneWidget);
    expect(find.textContaining('% holdings'), findsNothing);

    performanceAvailable = true;
    accounts.requestIbkrRefresh();
    await tester.pumpAndSettle();

    expect(performanceLoads, greaterThan(failedPerformanceLoads));
    expect(ibkrLoads, 1);
    expect(find.textContaining('10,100'), findsWidgets);
    expect(allRatesFromUsd['NZD'], closeTo(10100 / 5800, 1e-9));
    expect(find.text('+11.69%'), findsOneWidget);
    expect(find.textContaining('TWR'), findsNothing);
    expect(find.text('History unavailable'), findsNothing);

    final refreshedIbkrLoads = ibkrLoads;
    final refreshedPerformanceLoads = performanceLoads;
    await tester.tap(find.text('5d'));
    await tester.pumpAndSettle();
    expect(performanceLoads, refreshedPerformanceLoads);

    final successfulPerformanceLoads = performanceLoads;
    await tester.tap(find.text('10y'));
    await tester.pumpAndSettle();

    expect(ibkrLoads, refreshedIbkrLoads);
    expect(performanceLoads, successfulPerformanceLoads);
  });

  testWidgets('IBKR portfolio summary shows concise broker return', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({
      'ibkrAccountConfigs':
          '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
      'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
      'chartPeriodYears': 0,
      'chartPeriodMonths': 1,
      'chartPeriodDays': 0,
    });
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(879, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = testAccountManager();
    await accounts.init();
    final cachedPosition = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition],
      const IbkrAccountValue(value: 333989.91, currency: 'NZD'),
      netLiquidationUsd: 196500,
    );
    final now = DateTime.now();
    await seedTestCandle(
      'VOO',
      DateTime(now.year, now.month, now.day),
      550,
    );

    var performanceLoads = 0;
    Future<IbkrPerformanceSeries> performanceLoader(
      IbkrAccountConfig _,
      String period,
    ) async {
      performanceLoads++;
      expect(period, '1Y');
      return IbkrPerformanceSeries(
        period: period,
        measure: 'TWR',
        currency: 'NZD',
        startDate: DateTime(2026, 8, 17),
        startNav: 300000,
        dates: [DateTime(2026, 8, 18), DateTime(2026, 9, 16)],
        nav: const [300000, 340000],
        cashFlows: const [0, 100000],
        returnDates: [DateTime(2026, 8, 18), DateTime(2026, 9, 16)],
        returns: const [0, 0.0549],
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChartsPage(
              ibkrLoader: (_) async => throw StateError('cache should be used'),
              ibkrPerformanceLoader: performanceLoader,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageList = tester
        .widgetList<ListView>(find.byType(ListView))
        .singleWhere((listView) => listView.scrollDirection == Axis.vertical);
    final pagePadding = pageList.padding! as EdgeInsets;
    expect(pagePadding.left, 0);
    expect(pagePadding.right, 0);
    final summaryPadding = tester.widget<Padding>(
      find.byKey(const Key('portfolio-summary-content')),
    );
    final summaryInsets = summaryPadding.padding as EdgeInsets;
    expect(summaryInsets.left, 32);
    expect(summaryInsets.right, 32);
    expect(performanceLoads, greaterThan(0));
    expect(find.text('+5.49%'), findsOneWidget);
    expect(find.textContaining('TWR'), findsNothing);
    expect(find.textContaining('return excl. transfers'), findsNothing);
    expect(find.textContaining('holdings change'), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(find.textContaining('value change'), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('exact ticker fallback is available while search is loading', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    final search = find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(EditableText),
    );
    await tester.enterText(search, 'GLD');
    await tester.pump();

    expect(find.text('Use "GLD" anyway'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Use "GLD" anyway'), findsNothing);
  });

  testWidgets('empty ticker fallback stays hidden before typing', (
    WidgetTester tester,
  ) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchBar));
    await tester.pump();

    expect(find.text('Use "" anyway'), findsNothing);
  });

  test('chart axis percentages compact values from one thousand', () {
    expect(fmtChartAxisPercent(999), '+999%');
    expect(fmtChartAxisPercent(8), '+8%');
    expect(fmtChartAxisPercent(8.5), '+8.5%');
    expect(fmtChartAxisPercent(1000), '+1K%');
    expect(fmtChartAxisPercent(35000), '+35K%');
    expect(fmtChartAxisPercent(350000), '+350K%');
    expect(fmtChartAxisPercent(-350000), '-350K%');
  });

  testWidgets('desktop charts expose a manual refresh button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});

    final accounts = testAccountManager();
    await accounts.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MaterialApp(home: Scaffold(body: ChartsPage())),
      ),
    );
    await tester.pump();
    await tester.pump();

    final refresh = find.byTooltip('Refresh');
    expect(refresh, findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: refresh,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(tester.takeException(), null);
  });
}
