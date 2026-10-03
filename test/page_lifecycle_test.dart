import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

IbkrPortfolioSnapshot _snapshot(String account) => IbkrPortfolioSnapshot(
      account: account,
      positions: [
        const IbkrPosition(
          symbol: 'VOO',
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

IbkrPerformanceSeries _performance() => IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: DateTime(2025, 10, 3),
      startNav: 90,
      dates: [DateTime(2026, 10, 2)],
      nav: const [100],
      returnDates: [DateTime(2025, 10, 3), DateTime(2026, 10, 2)],
      returns: const [0, 0.1],
    );

Position _position() => Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 1,
      avgCost: 90,
      currentPrice: 100,
      firstBuyDate: DateTime(2025, 10, 3),
      lastBuyDate: DateTime(2026, 10, 2),
    );

Future<AccountManager> _configuredAccount() async {
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

Widget _app(AccountManager accounts, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

class _LifecycleTabs extends StatefulWidget {
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)
      chartPortfolioLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)
      chartPerformanceLoader;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)
      portfolioLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)
      portfolioPerformanceLoader;

  const _LifecycleTabs({
    required this.chartPortfolioLoader,
    required this.chartPerformanceLoader,
    required this.portfolioLoader,
    required this.portfolioPerformanceLoader,
  });

  @override
  State<_LifecycleTabs> createState() => _LifecycleTabsState();
}

class _LifecycleTabsState extends State<_LifecycleTabs> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    _controller.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              key: const Key('charts-tab'),
              onPressed: () => _select(0),
              child: const Text('Charts'),
            ),
            TextButton(
              key: const Key('portfolio-tab'),
              onPressed: () => _select(1),
              child: const Text('Portfolio'),
            ),
          ],
        ),
        Expanded(
          child: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ChartsPage(
                key: const ValueKey('charts-page'),
                isActive: _index == 0,
                ibkrLoader: widget.chartPortfolioLoader,
                ibkrPerformanceLoader: widget.chartPerformanceLoader,
              ),
              PortfolioPage(
                key: const ValueKey('portfolio-page'),
                isActive: _index == 1,
                ibkrLoader: widget.portfolioLoader,
                ibkrPerformanceLoader: widget.portfolioPerformanceLoader,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tab switching does not let the hidden portfolio fetch', (
    tester,
  ) async {
    await seedTestSqlite({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = await _configuredAccount();
    var chartPortfolioLoads = 0;
    var portfolioLoads = 0;
    var portfolioPerformanceLoads = 0;

    await tester.pumpWidget(
      _app(
        accounts,
        _LifecycleTabs(
          chartPortfolioLoader: (_) async {
            chartPortfolioLoads++;
            throw StateError('chart load deliberately leaves cache empty');
          },
          chartPerformanceLoader: (_, __) async => _performance(),
          portfolioLoader: (_) async {
            portfolioLoads++;
            return _snapshot('Default');
          },
          portfolioPerformanceLoader: (_, __) async {
            portfolioPerformanceLoads++;
            return _performance();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(chartPortfolioLoads, greaterThan(0));
    expect(portfolioLoads, 0);
    expect(portfolioPerformanceLoads, 0);
    final chartLoadsBeforeSwitch = chartPortfolioLoads;

    await tester.tap(find.byKey(const Key('portfolio-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(portfolioLoads, 1);
    expect(portfolioPerformanceLoads, 1);
    expect(chartPortfolioLoads, chartLoadsBeforeSwitch);
  });

  testWidgets('inactive portfolio ignores app resume', (tester) async {
    await seedTestSqlite({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = await _configuredAccount();
    await accounts.cachePortfolio(
      'Default',
      [_position()],
      const IbkrAccountValue(value: 100, currency: 'USD'),
      netLiquidationUsd: 100,
    );
    await accounts.cacheIbkrPerformance('Default', _performance());
    var portfolioLoads = 0;
    var performanceLoads = 0;
    const key = ValueKey('portfolio-lifecycle');

    Widget page(bool isActive) => _app(
          accounts,
          PortfolioPage(
            key: key,
            isActive: isActive,
            ibkrLoader: (_) async {
              portfolioLoads++;
              return _snapshot('Default');
            },
            ibkrPerformanceLoader: (_, __) async {
              performanceLoads++;
              return _performance();
            },
          ),
        );

    await tester.pumpWidget(page(false));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));

    expect(portfolioLoads, 0);
    expect(performanceLoads, 0);

    await tester.pumpWidget(page(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(portfolioLoads, 0);
    expect(performanceLoads, 0);

    await tester.pumpWidget(page(false));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));

    expect(portfolioLoads, 0);
    expect(performanceLoads, 0);
  });

  testWidgets('holdings reactivation performs one preload', (tester) async {
    await seedTestSqlite({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = testAccountManager();
    await accounts.init();
    var positionLoads = 0;
    const key = ValueKey('holdings-lifecycle');

    Widget page(bool isActive) => _app(
          accounts,
          HoldingsPage(
            key: key,
            isActive: isActive,
            positionsLoader: (_) async {
              positionLoads++;
              return [_position()];
            },
          ),
        );

    await tester.pumpWidget(page(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(positionLoads, 1);

    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(positionLoads, 1);

    await tester.pumpWidget(page(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(positionLoads, 2);
  });

  testWidgets('deactivating charts stops follow-on broker requests', (
    tester,
  ) async {
    await seedTestSqlite({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = testAccountManager();
    await accounts.init();
    await accounts.addAccount('Bot');
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://default.example.test',
        token: 'secret-token',
      ),
    );
    await accounts.setIbkrConfig(
      'Bot',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://bot.example.test',
        token: 'secret-token',
      ),
    );

    final firstLoad = Completer<IbkrPortfolioSnapshot>();
    var defaultLoads = 0;
    var botLoads = 0;
    const key = ValueKey('charts-lifecycle');

    Future<IbkrPortfolioSnapshot> loader(IbkrAccountConfig config) {
      if (config.baseUrl.contains('default')) {
        defaultLoads++;
        return firstLoad.future;
      }
      botLoads++;
      return Future.value(_snapshot('Bot'));
    }

    Widget page(bool isActive) => _app(
          accounts,
          ChartsPage(
            key: key,
            isActive: isActive,
            ibkrLoader: loader,
            ibkrPerformanceLoader: (_, __) async => _performance(),
          ),
        );

    await tester.pumpWidget(page(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(defaultLoads, 1);
    expect(botLoads, 0);

    await tester.pumpWidget(page(false));
    await tester.pump();
    firstLoad.complete(_snapshot('Default'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(defaultLoads, 1);
    expect(botLoads, 0);
  });
}
