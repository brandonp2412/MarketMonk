import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart' as app;
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<TickersCompanion> mockTickers = [
  TickersCompanion.insert(
    amount: 5,
    change: 0.66,
    name: 'GameStop',
    symbol: 'GME',
    price: 30.25,
  ),
  TickersCompanion.insert(
    amount: 10,
    change: -0.85,
    name: 'Apple Inc.',
    symbol: 'AAPL',
    price: 176.75,
  ),
  TickersCompanion.insert(
    amount: 3,
    change: 1.15,
    name: 'Tesla Inc.',
    symbol: 'TSLA',
    price: 243.00,
  ),
  TickersCompanion.insert(
    amount: 15,
    change: 0.24,
    name: 'Microsoft Corporation',
    symbol: 'MSFT',
    price: 337.35,
  ),
  TickersCompanion.insert(
    amount: 8,
    change: -0.39,
    name: 'Amazon.com Inc.',
    symbol: 'AMZN',
    price: 129.40,
  ),
];

List<CandlesCompanion> mockCandles = [
  CandlesCompanion.insert(
    symbol: 'GME',
    date: DateTime.now(),
    close: const Value(30.45),
  ),
  CandlesCompanion.insert(
    symbol: 'GME',
    date: DateTime.now().subtract(const Duration(days: 1)),
    close: const Value(30.25),
  ),
  CandlesCompanion.insert(
    symbol: 'GME',
    date: DateTime.now().subtract(const Duration(days: 2)),
    close: const Value(30.15),
  ),
  CandlesCompanion.insert(
    symbol: 'AAPL',
    date: DateTime.now(),
    close: const Value(175.25),
  ),
  CandlesCompanion.insert(
    symbol: 'AAPL',
    date: DateTime.now().subtract(const Duration(days: 1)),
    close: const Value(176.75),
  ),
  CandlesCompanion.insert(
    symbol: 'AAPL',
    date: DateTime.now().subtract(const Duration(days: 2)),
    close: const Value(177.25),
  ),
  CandlesCompanion.insert(
    symbol: 'TSLA',
    date: DateTime.now(),
    close: const Value(245.80),
  ),
  CandlesCompanion.insert(
    symbol: 'TSLA',
    date: DateTime.now().subtract(const Duration(days: 1)),
    close: const Value(243.00),
  ),
  CandlesCompanion.insert(
    symbol: 'TSLA',
    date: DateTime.now().subtract(const Duration(days: 2)),
    close: const Value(241.50),
  ),
  CandlesCompanion.insert(
    symbol: 'MSFT',
    date: DateTime.now(),
    close: const Value(338.15),
  ),
  CandlesCompanion.insert(
    symbol: 'MSFT',
    date: DateTime.now().subtract(const Duration(days: 1)),
    close: const Value(337.35),
  ),
  CandlesCompanion.insert(
    symbol: 'MSFT',
    date: DateTime.now().subtract(const Duration(days: 2)),
    close: const Value(336.85),
  ),
  CandlesCompanion.insert(
    symbol: 'AMZN',
    date: DateTime.now(),
    close: const Value(128.90),
  ),
  CandlesCompanion.insert(
    symbol: 'AMZN',
    date: DateTime.now().subtract(const Duration(days: 1)),
    close: const Value(129.40),
  ),
  CandlesCompanion.insert(
    symbol: 'AMZN',
    date: DateTime.now().subtract(const Duration(days: 2)),
    close: const Value(129.80),
  ),
];

enum TabBarState { chart, portfolio }

Future<void> appWrapper() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'theme': 'ThemeMode.dark',
    'systemColors': false,
    'curveLines': true,
  });
  final settings = SettingsState();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const app.MyApp(),
    ),
  );
}

BuildContext getBuildContext(WidgetTester tester, TabBarState? tabBarState) {
  switch (tabBarState) {
    case TabBarState.chart:
      return (tester.state(find.byType(ChartPage)) as ChartPageState).context;
    case TabBarState.portfolio:
      return (tester.state(find.byType(PortfolioPage)) as PortfolioPageState)
          .context;
    case null:
      break;
  }

  return tester.element(find.byType(TabBarView));
}

void navigateTo({required BuildContext context, required Widget page}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => page,
    ),
  );
}

Future<void> generateScreenshot({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required String screenshotName,
  required TabBarState tabBarState,
  Future<void> Function(BuildContext context)? navigateToPage,
  bool skipSettle = false,
}) async {
  await appWrapper();
  await tester.pumpAndSettle();

  final controllerState = getBuildContext(tester, null);
  DefaultTabController.of(controllerState).index = tabBarState.index;
  await tester.pumpAndSettle();

  if (navigateToPage != null) {
    final navState = getBuildContext(tester, tabBarState);
    await navigateToPage(navState);
  }

  skipSettle ? await tester.pump() : await tester.pumpAndSettle();
  await binding.convertFlutterSurfaceToImage();
  skipSettle ? await tester.pump() : await tester.pumpAndSettle();
  await binding.takeScreenshot(screenshotName);
}

void main() {
  IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    app.db = Database.connect(NativeDatabase.memory());
    await app.db.candles.insertAll(mockCandles);
    await app.db.tickers.insertAll(mockTickers);

    print(await (app.db.tickers.select()).get());
  });

  group("Generate default screenshots ", () {
    testWidgets(
      "ChartPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '1_en-US',
        tabBarState: TabBarState.chart,
      ),
    );

    testWidgets(
      "PortfolioPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '2_en-US',
        navigateToPage: (context) async => navigateTo(
          context: context,
          page: const PortfolioPage(),
        ),
        tabBarState: TabBarState.portfolio,
      ),
    );

    testWidgets(
      "SettingsPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '3_en-US',
        navigateToPage: (context) async => navigateTo(
          context: context,
          page: const SettingsPage(),
        ),
        tabBarState: TabBarState.portfolio,
      ),
    );

    testWidgets(
      "EditTickerPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '4_en-US',
        navigateToPage: (context) async => navigateTo(
          context: context,
          page: const EditTickerPage(symbol: 'GME'),
        ),
        tabBarState: TabBarState.portfolio,
      ),
    );
  });
}
