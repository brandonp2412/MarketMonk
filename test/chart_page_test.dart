import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Regression test for issue #35: the chart page's first frame can be laid
  // out with degenerate constraints (e.g. before the Linux window reaches its
  // real size). The search-bar overlay height must be re-measured once the
  // window resizes, otherwise the time chips stay stuck under the search bar.
  testWidgets(
    'time chips stay below the search bar after a degenerate first frame',
    (WidgetTester tester) async {
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = AccountManager();

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
    },
  );

  testWidgets('IBKR chart retries broker history without synthetic fallback', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ibkrAccountConfigs':
          '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
      'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
      'displayCurrency': 'NZD',
      'visibleCurrencies': ['NZD'],
      'exchangeRate_NZD': 1.7,
    });
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = AccountManager();
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
    await db.into(db.candles).insert(
          CandlesCompanion.insert(
            symbol: 'VOO',
            date: DateTime(now.year, now.month, now.day - 20),
            close: const Value(500),
          ),
        );
    await db.into(db.candles).insert(
          CandlesCompanion.insert(
            symbol: 'VOO',
            date: DateTime(now.year, now.month, now.day),
            close: const Value(550),
          ),
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

    var performanceLoads = 0;
    var performanceAvailable = false;
    Future<IbkrPerformanceSeries> performanceLoader(
      IbkrAccountConfig _,
      String period,
    ) async {
      performanceLoads++;
      expect(period, '1Y');
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

    expect(ibkrLoads, 1);
    expect(find.textContaining('10,100'), findsWidgets);
    expect(allRatesFromUsd['NZD'], closeTo(10100 / 5800, 1e-9));
    final failedPerformanceLoads = performanceLoads;
    expect(failedPerformanceLoads, greaterThan(0));
    expect(find.text('History unavailable'), findsOneWidget);
    expect(find.textContaining('% holdings'), findsNothing);

    performanceAvailable = true;
    await tester.tap(find.text('5d'));
    await tester.pumpAndSettle();

    expect(performanceLoads, greaterThan(failedPerformanceLoads));
    expect(find.textContaining('+11.69% TWR'), findsOneWidget);
    expect(find.text('History unavailable'), findsNothing);

    final successfulPerformanceLoads = performanceLoads;
    await tester.tap(find.text('10y'));
    await tester.pumpAndSettle();

    expect(ibkrLoads, 1);
    expect(performanceLoads, successfulPerformanceLoads);
  });

  testWidgets('IBKR portfolio summary uses broker TWR when available', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ibkrAccountConfigs':
          '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
      'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
      'chartPeriodYears': 0,
      'chartPeriodMonths': 1,
      'chartPeriodDays': 0,
    });
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = AccountManager();
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
    await db.into(db.candles).insert(
          CandlesCompanion.insert(
            symbol: 'VOO',
            date: DateTime(now.year, now.month, now.day),
            close: const Value(550),
          ),
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
        startNav: 336605.45,
        dates: [DateTime(2026, 8, 18), DateTime(2026, 9, 16)],
        nav: const [335900, 333989.91],
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

    expect(performanceLoads, greaterThan(0));
    expect(find.textContaining('+5.49% TWR'), findsOneWidget);
  });

  testWidgets('exact ticker fallback is available while search is loading', (
    WidgetTester tester,
  ) async {
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final accounts = AccountManager();

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

    await db.close();
  });

  testWidgets('empty ticker fallback stays hidden before typing', (
    WidgetTester tester,
  ) async {
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final accounts = AccountManager();

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

    await tester.tap(find.text('Search stocks'));
    await tester.pump();

    expect(find.text('Use "" anyway'), findsNothing);

    await db.close();
  });
}
