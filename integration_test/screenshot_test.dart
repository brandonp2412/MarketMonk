import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/main.dart' as app;
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _mockToday = DateTime.now();

List<TradesCompanion> mockTrades = [
  TradesCompanion.insert(
    quantity: 5,
    tradeDate: _mockToday.subtract(const Duration(days: 210)),
    tradeType: 'open',
    name: 'GameStop',
    symbol: 'GME',
    price: 30.25,
  ),
  TradesCompanion.insert(
    quantity: 10,
    tradeDate: _mockToday.subtract(const Duration(days: 196)),
    tradeType: 'open',
    name: 'Apple Inc.',
    symbol: 'AAPL',
    price: 176.75,
  ),
  TradesCompanion.insert(
    quantity: 3,
    tradeDate: _mockToday.subtract(const Duration(days: 182)),
    tradeType: 'open',
    name: 'Tesla Inc.',
    symbol: 'TSLA',
    price: 243.00,
  ),
  TradesCompanion.insert(
    quantity: 15,
    tradeDate: _mockToday.subtract(const Duration(days: 168)),
    tradeType: 'open',
    name: 'Microsoft Corporation',
    symbol: 'MSFT',
    price: 337.35,
  ),
  TradesCompanion.insert(
    quantity: 8,
    tradeDate: _mockToday.subtract(const Duration(days: 154)),
    tradeType: 'open',
    name: 'Amazon.com Inc',
    symbol: 'AMZN',
    price: 129.40,
  ),
];

List<CandlesCompanion> _mockCandlesFor(
  String symbol,
  double basePrice,
  List<double> movement,
) => [
  for (var index = 0; index < movement.length; index++)
    CandlesCompanion.insert(
      symbol: symbol,
      date: _mockToday.subtract(
        Duration(days: (movement.length - 1 - index) * 14),
      ),
      close: Value(basePrice + movement[index]),
    ),
];

List<CandlesCompanion> mockCandles = [
  ..._mockCandlesFor('GME', 30.0, [
    -2.4,
    -1.1,
    0.6,
    -0.3,
    1.8,
    0.9,
    2.6,
    1.7,
    3.4,
    2.5,
    4.2,
    3.7,
    5.1,
  ]),
  ..._mockCandlesFor('AAPL', 175.0, [
    -8.0,
    -4.5,
    -6.0,
    -1.5,
    2.0,
    0.5,
    4.0,
    7.5,
    5.0,
    9.0,
    12.0,
    10.0,
    15.0,
  ]),
  ..._mockCandlesFor('TSLA', 242.0, [
    -18.0,
    -9.0,
    -13.0,
    3.0,
    15.0,
    8.0,
    22.0,
    11.0,
    28.0,
    18.0,
    34.0,
    25.0,
    40.0,
  ]),
  ..._mockCandlesFor('MSFT', 337.0, [
    -15.0,
    -8.0,
    -11.0,
    -3.0,
    5.0,
    2.0,
    10.0,
    14.0,
    11.0,
    19.0,
    23.0,
    20.0,
    28.0,
  ]),
  ..._mockCandlesFor('AMZN', 129.0, [
    -7.0,
    -3.0,
    -5.0,
    1.0,
    4.0,
    2.0,
    7.0,
    10.0,
    8.0,
    13.0,
    16.0,
    14.0,
    19.0,
  ]),
];

enum TabBarState { chart, portfolio, holdings }

Future<void> appWrapper() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'theme': 'ThemeMode.dark',
    'systemColors': false,
    'curveLines': true,
  });
  final settings = SettingsState();
  final accounts = AccountManager();
  await accounts.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: const app.MyApp(),
    ),
  );
}

BuildContext getBuildContext(WidgetTester tester, TabBarState? tabBarState) {
  switch (tabBarState) {
    case TabBarState.chart:
      return (tester.state(find.byType(ChartsPage)) as ChartsPageState).context;
    case TabBarState.portfolio:
      return (tester.state(find.byType(PortfolioPage)) as PortfolioPageState)
          .context;
    case null:
      break;
    case TabBarState.holdings:
      return (tester.state(find.byType(HoldingsPage)) as HoldingsPageState)
          .context;
  }

  return tester.element(find.byType(PageView));
}

void navigateTo({required BuildContext context, required Widget page}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
}

Future<void> generateScreenshot({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required String screenshotName,
  required TabBarState tabBarState,
  Future<void> Function(BuildContext context)? navigateToPage,
}) async {
  await appWrapper();
  await tester.pumpAndSettle();

  final tabLabel = switch (tabBarState) {
    TabBarState.chart => 'Charts',
    TabBarState.portfolio => 'Portfolio',
    TabBarState.holdings => 'Holdings',
  };
  await tester.tap(find.bySemanticsLabel(tabLabel));
  await tester.pumpAndSettle();

  if (navigateToPage != null) {
    final navState = getBuildContext(tester, tabBarState);
    if (!navState.mounted) return;
    await navigateToPage(navState);
  }

  await tester.pumpAndSettle();

  if (tabBarState == TabBarState.chart && navigateToPage == null) {
    final chartFinder = find.byType(LineChart);
    expect(chartFinder, findsWidgets);
    final chart = tester.widget<LineChart>(chartFinder.first);
    expect(
      chart.data.lineBarsData.any((bar) => bar.spots.length > 1),
      isTrue,
      reason: 'The README chart screenshot must contain a visible data series.',
    );
  }

  await binding.convertFlutterSurfaceToImage();
  await tester.pumpAndSettle();
  await binding.takeScreenshot(screenshotName);
}

void main() {
  IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    app.db = Database.connect(NativeDatabase.memory());
    for (final symbol in ['GME', 'AAPL', 'TSLA', 'MSFT', 'AMZN']) {
      cacheSymbolMeta(symbol, 'USD');
    }
    allRatesFromUsd['USD'] = 1.0;
    await app.db.candles.insertAll(mockCandles);
    await app.db.trades.insertAll(mockTrades);
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
        tabBarState: TabBarState.portfolio,
      ),
    );

    testWidgets(
      "SettingsPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '3_en-US',
        navigateToPage: (context) async =>
            navigateTo(context: context, page: const SettingsPage()),
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

    testWidgets(
      "HoldingsPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '5_en-US',
        tabBarState: TabBarState.holdings,
      ),
    );

    testWidgets(
      "HoldingHistoryPage",
      (tester) async => await generateScreenshot(
        binding: binding,
        tester: tester,
        screenshotName: '6_en-US',
        tabBarState: TabBarState.holdings,
        navigateToPage: (context) async => navigateTo(
          context: context,
          page: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'GME',
              name: "GameStop",
              position: Position(
                symbol: 'GME',
                name: 'GameStop',
                nativeCurrency: 'USD',
                netShares: 5,
                avgCost: 30.23,
                currentPrice: 30.23,
                firstBuyDate: DateTime.now(),
                lastBuyDate: DateTime.now(),
              ),
              trades: [
                Trade(
                  id: 1,
                  symbol: 'GME',
                  name: 'GameStop',
                  quantity: 5,
                  price: 30.23,
                  tradeType: 'open',
                  tradeDate: DateTime.now(),
                  realizedPL: 0.5,
                  commission: 0.02,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });
}
