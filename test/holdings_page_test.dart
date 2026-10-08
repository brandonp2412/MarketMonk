import 'dart:async';

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

  testWidgets('realized profits appear in holding details, not the mobile list',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    await accounts.cachePortfolio(
      'Default',
      [
        Position(
          symbol: 'VOO',
          name: 'Vanguard S&P 500',
          nativeCurrency: 'USD',
          netShares: 10,
          avgCost: 500,
          currentPrice: 550,
          firstBuyDate: DateTime(2025),
          lastBuyDate: DateTime(2026),
        ),
      ],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrTradeHistoryLoader: (_) async => IbkrTradeHistory(
              available: true,
              trades: [
                IbkrTrade(
                  symbol: 'VOO',
                  name: 'Vanguard S&P 500',
                  currency: 'USD',
                  conid: 42,
                  quantity: -1,
                  price: 550,
                  tradeType: 'SELL',
                  tradeDate: DateTime.now(),
                  realizedPnl: 42,
                  commission: 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VOO'), findsOneWidget);
    expect(find.textContaining('Realized'), findsNothing);

    await tester.tap(find.text('VOO'));
    await tester.pumpAndSettle();
    expect(find.text('Realized P/L today'), findsOneWidget);
    expect(find.text('Imported realized P/L'), findsOneWidget);
  });

  testWidgets('desktop closed holdings do not show realized P/L in the table',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    await accounts.cachePortfolio('Default', [], null);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrTradeHistoryLoader: (_) async => IbkrTradeHistory(
              available: true,
              trades: [
                IbkrTrade(
                  symbol: 'VOO',
                  name: 'Vanguard S&P 500',
                  currency: 'USD',
                  conid: 42,
                  quantity: -1,
                  price: 550,
                  tradeType: 'SELL',
                  tradeDate: DateTime.now(),
                  realizedPnl: 123,
                  commission: 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.rows, hasLength(1));
    expect(find.text('VOO'), findsOneWidget);
    final pnlCell = table.rows.single.cells[5].child as Align;
    expect((pnlCell.child! as Text).data, '—');
    expect(find.textContaining('Realized'), findsNothing);
  });

  testWidgets('cached IBKR positions show before trade history completes',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
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
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );

    final pendingTrades = Completer<IbkrTradeHistory>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrTradeHistoryLoader: (_) => pendingTrades.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('VOO'), findsOneWidget);
    expect(find.text('No IBKR stocks found'), findsNothing);

    pendingTrades.complete(
      const IbkrTradeHistory(available: false, trades: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('VOO'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'other');
    await tester.pump();
    expect(find.text('No IBKR stocks found'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'VOO');
    await tester.pump();
    expect(find.text('VOO'), findsNWidgets(2));
  });

  testWidgets('IBKR portfolio loads without local trade records',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    final pendingPortfolio = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrLoader: (_) => pendingPortfolio.future,
            ibkrTradeHistoryLoader: (_) async =>
                const IbkrTradeHistory(available: false, trades: []),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No IBKR stocks found'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pendingPortfolio.complete(
      const IbkrPortfolioSnapshot(
        account: 'U1234',
        positions: [
          IbkrPosition(
            symbol: 'NVDA',
            securityType: 'STK',
            currency: 'USD',
            exchange: 'NASDAQ',
            conid: 1234,
            quantity: 5,
            marketPrice: 100,
            marketValue: 500,
            averageCost: 90,
            unrealizedPnl: 50,
            realizedPnl: 0,
          ),
        ],
        summary: {},
        ledger: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('No IBKR stocks found'), findsNothing);
  });

  testWidgets('switching IBKR accounts starts a separate holdings load',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.addAccount('IBKR Bot');
    for (final account in ['Default', 'IBKR Bot']) {
      await accounts.setIbkrConfig(
        account,
        IbkrAccountConfig(
          enabled: true,
          baseUrl: 'https://$account.example.test',
          token: 'test-token',
        ),
      );
      await accounts.cachePortfolio(
        account,
        [
          Position(
            symbol: account == 'Default' ? 'VOO' : 'NVDA',
            name: account == 'Default' ? 'Vanguard' : 'Nvidia',
            nativeCurrency: 'USD',
            netShares: 1,
            avgCost: 100,
            currentPrice: 110,
            firstBuyDate: DateTime(2025),
            lastBuyDate: DateTime(2026),
          ),
        ],
        const IbkrAccountValue(value: 110, currency: 'USD'),
      );
    }

    final firstAccountTrades = Completer<IbkrTradeHistory>();
    var secondAccountLoads = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrTradeHistoryLoader: (config) {
              if (config.baseUrl.contains('Default')) {
                return firstAccountTrades.future;
              }
              secondAccountLoads++;
              return Future.value(
                const IbkrTradeHistory(available: true, trades: []),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('VOO'), findsOneWidget);

    await accounts.switchAccount('IBKR Bot');
    await tester.pumpAndSettle();
    expect(secondAccountLoads, 1);
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('VOO'), findsNothing);

    firstAccountTrades.complete(
      const IbkrTradeHistory(available: false, trades: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('VOO'), findsNothing);
  });

  testWidgets('IBKR holdings stay visible when a refresh fails',
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
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
    );

    var portfolioLoads = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrLoader: (_) async {
              portfolioLoads++;
              throw StateError('backend offline');
            },
            ibkrTradeHistoryLoader: (_) async =>
                const IbkrTradeHistory(available: false, trades: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VOO'), findsOneWidget);

    accounts.requestIbkrRefresh();
    await tester.pumpAndSettle();

    expect(portfolioLoads, 1);
    expect(find.text('VOO'), findsOneWidget);
  });
}
