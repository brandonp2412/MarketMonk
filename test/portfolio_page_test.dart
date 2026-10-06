import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';
import 'test_log_support.dart';

IbkrPortfolioSnapshot snapshotFor(String account, String symbol) =>
    IbkrPortfolioSnapshot(
      account: account,
      positions: [
        IbkrPosition(
          symbol: symbol,
          securityType: 'STK',
          currency: 'USD',
          exchange: 'NASDAQ',
          conid: 1,
          quantity: 1,
          marketPrice: 100,
          marketValue: 100,
          averageCost: 90,
          unrealizedPnl: 10,
          realizedPnl: 0,
        ),
      ],
      summary: const {
        'netliquidation': {'value': 100.0, 'currency': 'USD'},
      },
      ledger: const {},
    );

Future<AccountManager> configuredTwoAccounts() async {
  final accounts = testAccountManager();
  await accounts.init();
  await accounts.addAccount('IBKR Bot');
  await accounts.setIbkrConfig(
    'Default',
    const IbkrAccountConfig(
      enabled: true,
      baseUrl: 'https://default.example.test',
      token: 'secret-token',
    ),
  );
  await accounts.setIbkrConfig(
    'IBKR Bot',
    const IbkrAccountConfig(
      enabled: true,
      baseUrl: 'https://bot.example.test',
      token: 'secret-token',
    ),
  );
  return accounts;
}

Future<void> seedCurrentCandle(String symbol) async {
  final now = DateTime.now();
  await testDatabase.into(testDatabase.candles).insert(
        CandlesCompanion.insert(
          symbol: symbol,
          date: DateTime(now.year, now.month, now.day),
          close: const Value(100),
        ),
      );
}

Future<IbkrPerformanceSeries> _performanceLoader(
  IbkrAccountConfig _,
  String period,
) async =>
    IbkrPerformanceSeries(
      period: period,
      measure: 'TWR',
      currency: 'USD',
      startDate: DateTime(2026, 1, 1),
      startNav: 100,
      dates: [DateTime(2026, 1, 1), DateTime(2026, 10, 1)],
      nav: const [100, 100],
      returnDates: [DateTime(2026, 1, 1), DateTime(2026, 10, 1)],
      returns: const [0, 0],
    );

PortfolioPage _portfolioPage({
  Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
  Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
      ibkrPerformanceLoader,
}) =>
    PortfolioPage(
      ibkrLoader: ibkrLoader,
      ibkrPerformanceLoader: ibkrPerformanceLoader ?? _performanceLoader,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Position cachedPosition() => Position(
        symbol: 'VOO',
        name: 'VANGUARD S&P 500 ETF',
        nativeCurrency: 'USD',
        netShares: 10,
        avgCost: 500,
        currentPrice: 550,
        firstBuyDate: DateTime(2025),
        lastBuyDate: DateTime(2026),
      );

  Future<AccountManager> configuredAccounts() async {
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
    return accounts;
  }

  Widget app(AccountManager accounts, Widget page) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(home: page),
      );

  testWidgets('portfolio exposes a loading state while uncached data loads', (
    tester,
  ) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    final pending = Completer<IbkrPortfolioSnapshot>();
    var loads = 0;

    await tester.pumpWidget(
      app(
        accounts,
        _portfolioPage(
          ibkrLoader: (_) {
            loads++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pump();

    expect(loads, 1);
    expect(find.bySemanticsLabel('Loading portfolio'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(loads, 1);
  });

  testWidgets(
    'portfolio renders persistent cache without waiting for refresh',
    (tester) async {
      await seedTestSqlite({});
      final accounts = await configuredAccounts();
      await accounts.cachePortfolio(
        'Default',
        [
          cachedPosition(),
        ],
        const IbkrAccountValue(value: 5500, currency: 'USD'),
      );
      final pending = Completer<IbkrPortfolioSnapshot>();

      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
      );
      await tester.pump();

      expect(find.text('VOO'), findsOneWidget);
      expect(find.text('VANGUARD S&P 500 ETF'), findsOneWidget);

      accounts.requestIbkrRefresh();
      await tester.pump();

      expect(find.text('VOO'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading portfolio'), findsOneWidget);

      pending.complete(snapshotFor('*****6552', 'VOO'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);
    },
  );

  testWidgets(
    'slow IBKR performance refresh does not keep portfolio loading',
    (tester) async {
      await seedTestSqlite({});
      final accounts = await configuredAccounts();
      await accounts.cachePortfolio(
        'Default',
        [cachedPosition()],
        const IbkrAccountValue(value: 5500, currency: 'USD'),
        netLiquidationUsd: 5500,
      );
      await accounts.cacheIbkrPerformance(
        'Default',
        await _performanceLoader(
          const IbkrAccountConfig(),
          '1Y',
        ),
      );

      final pendingPerformance = Completer<IbkrPerformanceSeries>();
      var performanceLoads = 0;

      await tester.pumpWidget(
        app(
          accounts,
          _portfolioPage(
            ibkrLoader: (_) async => snapshotFor('*****6552', 'VOO'),
            ibkrPerformanceLoader: (_, __) {
              performanceLoads++;
              return pendingPerformance.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(performanceLoads, 0);

      accounts.requestIbkrRefresh();
      await tester.pump();
      await tester.pump();

      expect(performanceLoads, 1);
      expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);
      expect(find.text('VOO'), findsWidgets);

      pendingPerformance.complete(
        await _performanceLoader(const IbkrAccountConfig(), '1Y'),
      );
      await tester.pumpAndSettle();
    },
  );

  test('portfolio cache survives AccountManager reinitialization', () async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
    );

    final reloaded = testAccountManager();
    await reloaded.init();
    final cached = reloaded.portfolioCacheFor('Default');

    expect(cached == null, isFalse);
    expect(cached!.positions.single.symbol, 'VOO');
    expect(cached.positions.single.currentPrice, 550);
    expect(cached.netLiquidation?.value, 5500);
    expect(cached.netLiquidationUsd, 5500);
  });

  testWidgets(
    'switching IBKR accounts never keeps the previous stream snapshot',
    (tester) async {
      await seedTestSqlite({
        'ibkrHistorySeeded:https://default.example.test:Default:VOO': true,
      });
      await seedCurrentCandle('VOO');

      final accounts = await configuredTwoAccounts();
      final botPending = Completer<IbkrPortfolioSnapshot>();
      Future<IbkrPortfolioSnapshot> loader(IbkrAccountConfig config) {
        if (config.baseUrl.contains('bot.example.test')) {
          return botPending.future;
        }
        return Future.value(snapshotFor('*****6552', 'VOO'));
      }

      await tester
          .pumpWidget(app(accounts, _portfolioPage(ibkrLoader: loader)));
      await tester.pumpAndSettle();

      expect(find.text('VOO'), findsWidgets);

      accounts.activeAccount = 'IBKR Bot';
      accounts.requestIbkrRefresh();
      await tester.pump();

      expect(find.text('VOO'), findsNothing);
      expect(find.bySemanticsLabel('Loading portfolio'), findsOneWidget);
    },
  );

  testWidgets(
    'an old IBKR request cannot overwrite the newly selected account cache',
    (tester) async {
      await seedTestSqlite({
        'ibkrHistorySeeded:https://default.example.test:Default:VOO': true,
      });
      await seedCurrentCandle('VOO');

      final accounts = await configuredTwoAccounts();
      final defaultPending = Completer<IbkrPortfolioSnapshot>();
      final botPending = Completer<IbkrPortfolioSnapshot>();
      Future<IbkrPortfolioSnapshot> loader(IbkrAccountConfig config) {
        if (config.baseUrl.contains('bot.example.test')) {
          return botPending.future;
        }
        return defaultPending.future;
      }

      await tester
          .pumpWidget(app(accounts, _portfolioPage(ibkrLoader: loader)));
      await tester.pump();

      accounts.activeAccount = 'IBKR Bot';
      accounts.requestIbkrRefresh();
      await tester.pump();

      defaultPending.complete(snapshotFor('*****6552', 'VOO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(accounts.portfolioCacheFor('IBKR Bot') == null, isTrue);
      expect(
        accounts.portfolioCacheFor('Default')?.positions.single.symbol,
        'VOO',
      );
      expect(find.text('VOO'), findsNothing);
    },
  );

  testWidgets(
    'portfolio shows a friendly IBKR error instead of exception text',
    (tester) async {
      silenceTalkerForTest();
      await seedTestSqlite({});

      final accounts = await configuredAccounts();

      await tester.pumpWidget(
        app(
          accounts,
          _portfolioPage(
            ibkrLoader: (_) async =>
                throw StateError('secret technical failure'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t load Interactive Brokers'), findsOneWidget);
      expect(
        find.text(
          'MarketMonk couldn’t load your portfolio from your IBKR server. '
          'Check the server connection, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('IBKR settings'), findsOneWidget);
      expect(find.textContaining('secret technical failure'), findsNothing);
      expect(find.textContaining('Bad state:'), findsNothing);
    },
  );

  testWidgets('portfolio uses split desktop layout at wide widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});

    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();

    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(find.text('VOO'), findsNWidgets(2));
    expect(find.text('Account value'), findsOneWidget);
    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('Return by holding'), findsOneWidget);
    expect(find.text('Filter holdings...'), findsNothing);
    expect(find.byType(Card), findsNWidgets(2));
    final refresh = find.byTooltip('Refresh');
    expect(refresh, findsOneWidget);
    expect(
      find.descendant(
        of: refresh,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.controller == null, false);
    expect(scrollbar.controller!.hasClients, true);
    final allocationList = tester.widget<ListView>(
      find.descendant(
        of: find.byType(Scrollbar),
        matching: find.byType(ListView),
      ),
    );
    expect(allocationList.padding, const EdgeInsets.only(right: 12));
    final pieFinder = find.byType(MarketDonutChart).first;
    final pie = tester.widget<MarketDonutChart>(pieFinder);
    expect(pie.radius, 75);
    final subtitleBottom = tester
        .getBottomLeft(find.text('How your stock portfolio is distributed'))
        .dy;
    final pieTop = tester.getTopLeft(pieFinder).dy;
    expect(pieTop - subtitleBottom, greaterThanOrEqualTo(28));
    expect(tester.takeException(), null);
  });

  testWidgets('portfolio reflows allocation at compact desktop widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(879, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});

    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();

    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('desktop-allocation-compact')),
      findsOneWidget,
    );
    final subtitleBottom = tester
        .getBottomLeft(find.text('How your stock portfolio is distributed'))
        .dy;
    final compactPieFinder = find.byType(MarketDonutChart).first;
    final pieTop = tester.getTopLeft(compactPieFinder).dy;
    expect(pieTop - subtitleBottom, greaterThanOrEqualTo(28));
    final compactPie = tester.widget<MarketDonutChart>(compactPieFinder);
    expect(compactPie.centerSpaceRadius, 48);
    expect(compactPie.radius, 54);
    expect(compactPie.selectedRadius, 60);
    expect(tester.takeException(), null);
  });

  testWidgets(
    'portfolio handles short compact desktop heights',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(879, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await seedTestSqlite({});

      final accounts = await configuredAccounts();
      await accounts.cachePortfolio(
        'Default',
        [cachedPosition()],
        const IbkrAccountValue(value: 5500, currency: 'USD'),
      );
      final pending = Completer<IbkrPortfolioSnapshot>();

      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('desktop-allocation-compact')),
        findsOneWidget,
      );
      expect(find.byType(MarketDonutChart), findsOneWidget);
      expect(find.text('VOO'), findsNWidgets(2));
      expect(tester.takeException(), null);
    },
  );
}
