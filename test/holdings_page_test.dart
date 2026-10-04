import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop holdings renders sortable data table', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await seedTestSqlite({});

    final accounts = testAccountManager();
    await accounts.init();
    final position = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            positionsLoader: (_) async => [position],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('VOO'), findsOneWidget);
    expect(find.text('VANGUARD S&P 500 ETF'), findsOneWidget);
    expect(find.text('Market value'), findsNWidgets(2));
    expect(find.text('Cost basis'), findsOneWidget);
    expect(find.text('Unrealized P/L'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Avg cost'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Return'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    final desktopPadding = tester.widget<Padding>(
      find.byKey(const Key('desktop-holdings-content')),
    );
    expect(desktopPadding.padding, const EdgeInsets.fromLTRB(24, 16, 24, 24));
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.controller == null, false);
    expect(scrollbar.controller!.hasClients, true);

    await tester.tap(find.text('Return'));
    await tester.pump();

    expect(tester.takeException(), null);
  });

  testWidgets('compact desktop holdings fits half-width content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(879, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await seedTestSqlite({});

    final accounts = testAccountManager();
    await accounts.init();
    final position = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            positionsLoader: (_) async => [position],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('Shares'), findsNothing);
    expect(find.text('Avg cost'), findsNothing);
    expect(find.text('Price'), findsNothing);
    expect(find.text('P/L'), findsOneWidget);
    expect(find.text('Return'), findsOneWidget);
    expect(tester.takeException(), null);

    await tester.tap(find.text('Return'));
    await tester.pump();
    expect(tester.takeException(), null);
  });

  testWidgets('desktop holdings matches portfolio cash-out P/L',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1;

    final accounts = testAccountManager();
    await accounts.init();
    final position = Position(
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
      [position],
      const IbkrAccountValue(value: 24278.20, currency: 'USD'),
    );
    await accounts.cacheIbkrPerformance(
      'Default',
      IbkrPerformanceSeries(
        period: '1Y',
        measure: 'TWR',
        currency: 'USD',
        startDate: DateTime(2026, 1, 1),
        startNav: 0,
        dates: [
          DateTime(2026, 1, 2),
          DateTime(2026, 1, 3),
          DateTime(2026, 1, 4),
        ],
        nav: const [3355.69, 3355.196063, 23326.951487],
        cashFlows: const [0, 0, 0],
        returnDates: [
          DateTime(2026, 1, 2),
          DateTime(2026, 1, 3),
          DateTime(2026, 1, 4),
        ],
        returns: const [0, -0.00014719, -0.00063536],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(positionsLoader: (_) async => [position]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'+$939.36'), findsOneWidget);
    expect(find.text(r'+$500.00'), findsOneWidget);
  });

  testWidgets('holdings menu exposes account picker on desktop',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'accounts': ['Default', 'Brokerage'],
    });

    final accounts = testAccountManager();
    await accounts.init();
    final position = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(positionsLoader: (_) async => [position]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('desktop-holdings-account-picker')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('holdings-menu-button')));
    await tester.pumpAndSettle();

    expect(accounts.activeAccount, 'Default');
    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(2));

    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Brokerage'),
    );
    await tester.pumpAndSettle();
    expect(accounts.activeAccount, 'Brokerage');
  });
}
