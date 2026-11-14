import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/portfolio_history.dart';
import 'package:market_monk/portfolio_intraday_cache.dart';
import 'package:market_monk/portfolio_period_picker.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
  Future<ShareResult> Function(ShareParams)? shareFile,
  Future<void> Function(File, List<int>)? writeShareFile,
  IntradayMarketData? intradayData,
  PortfolioCandleSync? historyCandleSync,
  Future<IbkrTradeHistory> Function(IbkrAccountConfig)? historyTradeLoader,
}) =>
    PortfolioPage(
      ibkrLoader: ibkrLoader,
      ibkrPerformanceLoader: ibkrPerformanceLoader ?? _performanceLoader,
      historyTradeLoader: historyTradeLoader ??
          (_) async => IbkrTradeHistory(
                available: true,
                trades: [
                  for (final trade in await profileDataRepository
                      .readTradesForAccount('Default'))
                    IbkrTrade(
                      symbol: trade.symbol,
                      name: trade.name,
                      currency: trade.rawCurrency ?? 'USD',
                      conid: trade.brokerConid ?? 0,
                      quantity: trade.quantity,
                      price: trade.price,
                      tradeType: trade.tradeType,
                      tradeDate: trade.tradeDate,
                      realizedPnl: trade.realizedPL,
                      commission: trade.commission,
                    ),
                ],
              ),
      historyCandleSync: historyCandleSync ?? (symbol, from, config) async {},
      historyRateLoader: (currency, date) async => 1,
      shareFile: shareFile,
      writeShareFile: writeShareFile,
      intradayData: intradayData ??
          IntradayMarketData(
            ibkrFetch: (config, symbol, days) async =>
                throw StateError('IBKR network disabled in tests'),
            ibkrPortfolioFetch: (config, days) async => const [],
            yahooGet: (uri) => throw StateError('network disabled in tests'),
            retryDelay: (_) async {},
          ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy cached IBKR portfolios get a one-time cash refresh', () {
    final cached = CachedPortfolioData(
      positions: const [],
      netLiquidation: null,
      cachedAt: DateTime.now(),
    );
    final oldJson = cached.toJson()..remove('cashChecked');
    expect(CachedPortfolioData.fromJson(oldJson).cashChecked, isFalse);
    expect(CachedPortfolioData.fromJson(cached.toJson()).cashChecked, isTrue);
  });

  Position cachedPosition({String name = 'VANGUARD S&P 500 ETF'}) => Position(
        symbol: 'VOO',
        name: name,
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

  Future<void> seedFortnightFixture(
    AccountManager accounts, {
    int days = 70,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - days);
    final dates = <DateTime>{
      start,
      for (final period in portfolioFortnightlyPeriods(now, start).skip(1))
        portfolioReturnCutoff(period, now)!,
      DateTime(now.year, now.month, now.day),
    }.toList()
      ..sort();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
    );
    await accounts.cacheIbkrPerformance(
      'Default',
      IbkrPerformanceSeries(
        period: '1Y',
        measure: 'TWR',
        currency: 'USD',
        startDate: start,
        startNav: 5500,
        dates: dates,
        nav: List.filled(dates.length, 5500),
        returnDates: dates,
        returns: List.filled(dates.length, 0.0),
      ),
    );
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    for (final date in dates) {
      await testDatabase.into(testDatabase.candles).insertOnConflictUpdate(
            CandlesCompanion.insert(
              symbol: 'VOO',
              date: date,
              close: const Value(550),
              rawCurrency: const Value('USD'),
            ),
          );
    }
  }

  Widget app(AccountManager accounts, Widget page) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(home: page),
      );

  testWidgets('IBKR cash stays in the mobile legend and donut', (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    allRatesFromUsd['NZD'] = 1.7;
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 9400, currency: 'NZD'),
      cashBalance: const IbkrAccountValue(value: 17, currency: 'NZD'),
      cashUsd: 10,
    );
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();
    expect(find.byKey(const Key('portfolio-ibkr-cash')), findsNothing);
    expect(find.byKey(const Key('portfolio-cash-summary')), findsNothing);
    final donut = tester.widget<MarketDonutChart>(
      find.byType(MarketDonutChart),
    );
    expect(donut.slices.length, 2);
    expect(donut.slices.any((slice) => slice.label == 'CASH'), isTrue);
    await tester.scrollUntilVisible(
      find.text('CASH'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CASH'), findsOneWidget);
  });

  testWidgets('portfolio shows a spinner while uncached remote data loads', (
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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
      expect(find.text('100.0%'), findsOneWidget);
      final mobileDonut = tester.widget<MarketDonutChart>(
        find.byType(MarketDonutChart),
      );
      expect(mobileDonut.radius, 60);
      expect(mobileDonut.selectedRadius, 75);
      expect(
        mobileDonut.centerSpaceRadius + mobileDonut.selectedRadius,
        lessThanOrEqualTo(260 / 2),
      );

      accounts.requestIbkrRefresh();
      await tester.pump();

      expect(find.text('VOO'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.complete(snapshotFor('*****6552', 'VOO'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);
    },
  );

  testWidgets('mobile donut selection label stays centered in the hole',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 1100);
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

    final donutCenter = tester.getCenter(find.byType(MarketDonutChart));
    await tester.tapAt(donutCenter + const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 300));

    final symbol = find.descendant(
      of: find.byType(SliverPersistentHeader),
      matching: find.text('VOO'),
    );
    expect(symbol, findsOneWidget);
    final labelCenter = tester.getCenter(symbol);
    expect((labelCenter.dx - donutCenter.dx).abs(), lessThan(2));
    expect((labelCenter.dy - donutCenter.dy).abs(), lessThan(30));
  });

  testWidgets('portfolio shows cached IBKR cash as an allocation slice', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 11000, currency: 'USD'),
      netLiquidationUsd: 11000,
      cashBalance: const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();
    expect(find.text('CASH'), findsOneWidget);
    expect(find.byKey(const Key('portfolio-cash-summary')), findsNothing);
    expect(find.text('50.0%'), findsNWidgets(2));
    final chart = tester.widget<MarketDonutChart>(
      find.byType(MarketDonutChart),
    );
    expect(chart.slices.map((slice) => slice.value), [5500, 5500]);
  });

  testWidgets('cash-only desktop portfolio includes cash without broker NAV', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [],
      null,
      cashBalance: const IbkrAccountValue(value: 3544.36, currency: 'USD'),
      cashUsd: 3544.36,
    );
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(find.text('Account value'), findsOneWidget);
    expect(find.text('Stock value'), findsOneWidget);
    expect(find.text('Market value'), findsNothing);
    expect(find.text(fmtCurrency(3544.36)), findsWidgets);
    const cash = IbkrAccountValue(value: 3544.36, currency: 'USD');
    expect(
      find.text('Cash · ${formatIbkrReportedCash(cash)}'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('desktop-portfolio-metrics')),
        matching: find.text(fmtCurrency(3544.36)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('tiny cash balance stays in the allocation legend and donut', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5501.1, currency: 'USD'),
      netLiquidationUsd: 5501.1,
      cashBalance: const IbkrAccountValue(value: 1.1, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();
    expect(find.byKey(const Key('portfolio-cash-summary')), findsNothing);
    expect(find.text('CASH'), findsOneWidget);
    final chart = tester.widget<MarketDonutChart>(
      find.byType(MarketDonutChart),
    );
    expect(
      chart.slices.singleWhere((slice) => slice.label == 'CASH').value,
      1.1,
    );
  });

  testWidgets('mobile portfolio lists positions without a filter field', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [
        cachedPosition(),
        Position(
          symbol: 'AAPL',
          name: 'Apple',
          nativeCurrency: 'USD',
          netShares: 2,
          avgCost: 100,
          currentPrice: 150,
          firstBuyDate: DateTime(2025),
          lastBuyDate: DateTime(2026),
        ),
      ],
      const IbkrAccountValue(value: 5800, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('VOO'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    final appleRow = find.ancestor(
      of: find.text('AAPL'),
      matching: find.byType(ListTile),
    );
    expect((tester.widget<ListTile>(appleRow).subtitle! as Text).data, '5.2%');
    expect(
      find.descendant(of: appleRow, matching: find.text('+50.00%')),
      findsOneWidget,
    );
    final trailing = tester.widget<ListTile>(appleRow).trailing! as Column;
    final valueText = trailing.children.first as Text;
    final returnText = trailing.children.last as Text;
    expect(valueText.style?.color, Colors.green);
    expect(returnText.style?.color, Colors.green);
    expect(find.byType(MarketDonutChart), findsOneWidget);
    expect(tester.takeException(), null);
  });

  for (final width in [700.0, 1400.0]) {
    testWidgets('portfolio profile picker switches at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await seedTestSqlite({});
      final accounts = await configuredTwoAccounts();
      for (final profile in accounts.accounts) {
        await accounts.cachePortfolio(
          profile,
          [
            cachedPosition(),
          ],
          const IbkrAccountValue(value: 5500, currency: 'USD'),
        );
      }

      final pending = Completer<IbkrPortfolioSnapshot>();
      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
      );
      await tester.pump();

      if (width == 1400) {
        expect(find.text('Default · Portfolio'), findsOneWidget);
        expect(find.text('1 position · 1 currency'), findsOneWidget);
      }
      final picker = find.byKey(const Key('portfolio-profile-picker'));
      expect(
        find.descendant(of: picker, matching: find.text('D')),
        findsOneWidget,
      );

      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('IBKR Bot'), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.text('IBKR Bot'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(accounts.activeAccount, 'IBKR Bot');
      if (width == 1400) {
        expect(find.text('IBKR Bot · Portfolio'), findsOneWidget);
      }
      expect(
        find.descendant(of: picker, matching: find.text('I')),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    });
  }

  testWidgets('uncached IBKR Bot periods load before its snapshot finishes', (
    tester,
  ) async {
    await seedTestSqlite({});
    final accounts = await configuredTwoAccounts();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 70);
    final dayAgo = portfolioReturnCutoff(10, now)!;
    for (final profile in accounts.accounts) {
      await accounts.cachePortfolio(
        profile,
        [cachedPosition()],
        const IbkrAccountValue(value: 5500, currency: 'USD'),
        netLiquidationUsd: 5500,
      );
    }
    await accounts.cacheIbkrPerformance(
      'Default',
      await _performanceLoader(const IbkrAccountConfig(), '1Y'),
    );
    await accounts.cacheIbkrTradeHistory(
      'IBKR Bot',
      IbkrTradeHistory(
        available: true,
        trades: [
          IbkrTrade(
            symbol: 'VOO',
            name: 'VOO',
            currency: 'USD',
            conid: 1,
            quantity: 10,
            price: 500,
            tradeType: 'open',
            tradeDate: start,
            realizedPnl: 0,
            commission: 0,
          ),
        ],
      ),
    );
    await testDatabase.into(testDatabase.candles).insert(
          CandlesCompanion.insert(
            symbol: 'VOO',
            date: dayAgo,
            close: const Value(540),
            rawCurrency: const Value('USD'),
          ),
        );
    final botPerformance = Completer<IbkrPerformanceSeries>();
    final botSnapshot = Completer<IbkrPortfolioSnapshot>();
    final cachedBars = [
      IbkrHistoricalSeries(
        symbol: 'VOO',
        currency: 'USD',
        candles: [
          for (final offset in [4, 2, 1])
            IbkrHistoricalCandle(
              date: now.toUtc().subtract(Duration(hours: offset)),
              open: 550,
              high: 550,
              low: 550,
              close: 550,
              volume: 0,
            ),
        ],
      ),
    ];
    var performanceRequests = 0;
    var snapshotRequests = 0;

    await tester.pumpWidget(
      app(
        accounts,
        _portfolioPage(
          ibkrLoader: (config) {
            if (config.baseUrl.contains('bot.example.test')) {
              snapshotRequests++;
              return botSnapshot.future;
            }
            return Future.value(snapshotFor('default', 'VOO'));
          },
          ibkrPerformanceLoader: (config, period) {
            if (config.baseUrl.contains('bot.example.test')) {
              performanceRequests++;
              return botPerformance.future;
            }
            return _performanceLoader(config, period);
          },
          intradayData: IntradayMarketData(
            ibkrPortfolioFetch: (config, days) async => cachedBars,
            ibkrFetch: (config, symbol, days) async => cachedBars.single,
            yahooGet: (_) => throw StateError('Unexpected Yahoo request'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PortfolioPeriodPicker>(
            find.byType(PortfolioPeriodPicker),
          )
          .loading,
      isFalse,
    );
    await accounts.switchAccount('IBKR Bot');
    accounts.requestIbkrRefresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(snapshotRequests, 1);
    expect(performanceRequests, 1);
    expect(accounts.ibkrPerformanceCacheFor('IBKR Bot', '1Y') == null, isTrue);
    expect(
      tester
          .widget<PortfolioPeriodPicker>(
            find.byType(PortfolioPeriodPicker),
          )
          .loading,
      isTrue,
    );
    expect(find.text('PRESENT'), findsOneWidget);
    expect(find.textContaining('FETCHING PAST PERIODS'), findsNothing);
    expect(
      find.byKey(const Key('portfolio-return-period')),
      findsOneWidget,
    );

    botPerformance.complete(
      IbkrPerformanceSeries(
        period: '1Y',
        measure: 'TWR',
        currency: 'USD',
        startDate: start,
        startNav: 5000,
        dates: [start, dayAgo, now],
        nav: const [5000, 5400, 5500],
        returnDates: [start, dayAgo, now],
        returns: const [0, .08, .1],
      ),
    );
    await tester.pumpAndSettle();
    expect(accounts.ibkrPerformanceCacheFor('IBKR Bot', '1Y') == null, isFalse);
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.loading, isFalse);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(
      [
        for (var i = 0; i <= slider.max; i++)
          slider.semanticFormatterCallback!(i.toDouble()),
      ],
      contains(contains('2W ago')),
    );
    expect(find.textContaining('LOADING HISTORY'), findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
    botSnapshot.complete(snapshotFor('bot', 'VOO'));
  });

  testWidgets('slow IBKR performance refresh does not keep portfolio loading', (
    tester,
  ) async {
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
      await _performanceLoader(const IbkrAccountConfig(), '1Y'),
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
    // Cached performance exists, but it may cover only a subset of dates.
    final pickerDuringRefresh = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(pickerDuringRefresh.loading, isTrue);
    expect(pickerDuringRefresh.labels, contains('2W'));
    expect(find.text('PRESENT'), findsOneWidget);

    pendingPerformance.complete(
      await _performanceLoader(const IbkrAccountConfig(), '1Y'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('LOADING HISTORY'), findsNothing);
    expect(
      tester
          .widget<PortfolioPeriodPicker>(find.byType(PortfolioPeriodPicker))
          .loading,
      isFalse,
    );
  });

  test('portfolio cache survives AccountManager reinitialization', () async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
      cashBalance: const IbkrAccountValue(value: 700, currency: 'USD'),
    );

    final reloaded = testAccountManager();
    await reloaded.init();
    final cached = reloaded.portfolioCacheFor('Default');

    expect(cached == null, isFalse);
    expect(cached!.positions.single.symbol, 'VOO');
    expect(cached.positions.single.currentPrice, 550);
    expect(cached.netLiquidation?.value, 5500);
    expect(cached.netLiquidationUsd, 5500);
    expect(
      cached.cashBalance,
      const IbkrAccountValue(value: 700, currency: 'USD'),
    );
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

      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: loader)),
      );
      await tester.pumpAndSettle();

      expect(find.text('VOO'), findsWidgets);

      accounts.activeAccount = 'IBKR Bot';
      accounts.requestIbkrRefresh();
      await tester.pump();

      expect(find.text('VOO'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
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

      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: loader)),
      );
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

  testWidgets('portfolio uses split desktop layout at wide widths', (
    tester,
  ) async {
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

    expect(find.text('VOO'), findsNWidgets(2));
    expect(find.text('Account value'), findsOneWidget);
    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('Return by holding'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
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
    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const Key('desktop-allocation-scrollbar')),
    );
    expect(scrollbar.controller == null, false);
    expect(scrollbar.controller!.hasClients, true);
    final allocationList = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const Key('desktop-allocation-scrollbar')),
        matching: find.byType(ListView),
      ),
    );
    expect(allocationList.padding, const EdgeInsets.only(right: 12));
    final returnScrollbar = tester.widget<Scrollbar>(
      find.byKey(const Key('desktop-return-scrollbar')),
    );
    expect(returnScrollbar.controller?.hasClients, true);
    final returnList = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const Key('desktop-return-scrollbar')),
        matching: find.byType(ListView),
      ),
    );
    expect(returnList.padding, const EdgeInsets.only(right: 24));
    final pieFinder = find.byType(MarketDonutChart).first;
    final pie = tester.widget<MarketDonutChart>(pieFinder);
    expect(pie.radius, 75);
    final subtitleBottom = tester.getBottomLeft(find.text('Allocation')).dy;
    final pieTop = tester.getTopLeft(pieFinder).dy;
    expect(pieTop - subtitleBottom, greaterThanOrEqualTo(28));
    expect(tester.takeException(), null);

    await tester.tap(find.byKey(const Key('desktop-return-VOO')));
    await tester.pump();
    expect(find.text('Trade History'), findsWidgets);

    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(tester.takeException(), null);
      expect(find.text('Return by holding'), findsOneWidget);
      expect(returnScrollbar.controller!.hasClients, isTrue);

      if (visit == 0) {
        await tester.tap(find.byKey(const Key('desktop-return-VOO')));
        await tester.pump();
        expect(find.text('Trade History'), findsWidgets);
      }
    }
  });

  for (final width in [700.0, 1000.0]) {
    testWidgets('portfolio period updates pie and allocation at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await seedTestSqlite({});
      final accounts = await configuredAccounts();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day - 100);
      final fortnight = portfolioReturnCutoff(-2, now)!;
      final historyDates = <DateTime>{
        start,
        for (final period in [7, 11, 8, 12, 9, 10])
          portfolioReturnCutoff(period, now)!,
        for (final period in portfolioFortnightlyPeriods(now, start).skip(1))
          portfolioReturnCutoff(period, now)!,
        DateTime(now.year, now.month, now.day),
      }.toList()
        ..sort();
      await accounts.cachePortfolio(
        'Default',
        [
          cachedPosition(),
          Position(
            symbol: 'MSFT',
            name: 'Microsoft',
            nativeCurrency: 'USD',
            netShares: 10,
            avgCost: 100,
            currentPrice: 100,
            firstBuyDate: DateTime(2025),
            lastBuyDate: DateTime(2026),
          ),
        ],
        const IbkrAccountValue(value: 12100, currency: 'USD'),
      );
      await accounts.cacheIbkrPerformance(
        'Default',
        IbkrPerformanceSeries(
          period: '1Y',
          measure: 'TWR',
          currency: 'USD',
          startDate: start,
          startNav: 0,
          dates: historyDates,
          nav: [
            for (final date in historyDates)
              switch (true) {
                _ when date == historyDates.last => 12100,
                _ when date.isBefore(fortnight) => 10000,
                _ => 11000,
              },
          ],
          returnDates: historyDates,
          returns: [
            for (final date in historyDates)
              switch (true) {
                _ when date == historyDates.last => .21,
                _ when date.isBefore(fortnight) => 0,
                _ => .1,
              },
          ],
        ),
      );
      await testDatabase.addTrade(
        profileId: (await testDatabase.readProfileByName('Default'))!.id,
        symbol: 'OLD',
        name: 'Old holding',
        quantity: -10,
        price: 100,
        tradeType: 'sell',
        tradeDate: now,
        realizedPL: 0,
        commission: 0,
        rawCurrency: 'USD',
      );
      for (final period in [
        -1,
        7,
        8,
        9,
        10,
        11,
        12,
        ...portfolioFortnightlyPeriods(now, start).skip(1),
      ]) {
        final date = period == -1 ? start : portfolioReturnCutoff(period, now)!;
        for (final symbol in ['VOO', 'MSFT', 'OLD']) {
          await testDatabase.into(testDatabase.candles).insertOnConflictUpdate(
                CandlesCompanion.insert(
                  symbol: symbol,
                  date: date,
                  rawCurrency: const Value('USD'),
                  close: Value(
                    switch (true) {
                      _ when (symbol == 'VOO') && (period == -2) => 200.0,
                      _ when (symbol == 'VOO') => 100.0,
                      _ when (symbol == 'MSFT') && (period == -2) => 100.0,
                      _ when (symbol == 'MSFT') => 300.0,
                      _ when period == -2 => 100.0,
                      _ => 400.0,
                    },
                  ),
                ),
              );
        }
      }
      final pending = Completer<IbkrPortfolioSnapshot>();
      await tester.pumpWidget(
        app(accounts, _portfolioPage(ibkrLoader: (_) => pending.future)),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(const Key('portfolio-return-period'));
      var slider = tester.widget<Slider>(finder);
      expect(slider.divisions, 7);
      expect(slider.semanticFormatterCallback!(0), 'Now, current allocation');
      for (var index = 1; index <= slider.max; index++) {
        expect(
          slider.semanticFormatterCallback!(index.toDouble()),
          contains('${index * 2}W ago'),
        );
      }

      expect(find.textContaining('Open holdings returns'), findsNothing);
      expect(
        find.textContaining('purchase history when available'),
        findsNothing,
      );
      Map<String, double> pieValues() => {
            for (final slice in tester
                .widget<MarketDonutChart>(find.byType(MarketDonutChart))
                .slices)
              slice.label: slice.value,
          };
      expect(pieValues(), {'VOO': 5500, 'MSFT': 1000});
      if (width >= 840) {
        expect(find.text(fmtNativeCurrency(12100, 'USD')), findsOneWidget);
      } else {
        expect(
          tester
              .widget<Text>(find.byKey(const Key('portfolio-total-value')))
              .data,
          fmtNativeCurrency(12100, 'USD'),
        );
      }
      slider.onChanged!(6);
      await tester.pump();
      expect(
        find.text(
          DateFormat('d MMM yyyy').format(portfolioReturnCutoff(-7, now)!),
        ),
        findsOneWidget,
      );
      expect(find.text('+21.00%'), findsNothing);
      expect(
        pieValues(),
        {'VOO': 1000, 'MSFT': 3000, 'OLD': 4000, 'CASH': 2000},
      );
      final chartAnimation = tester
          .widget<AnimatedBuilder>(
            find.descendant(
              of: find.byType(MarketDonutChart),
              matching: find.byType(AnimatedBuilder),
            ),
          )
          .animation as Animation<double>;
      expect(chartAnimation.value, 0);
      await tester.pump(const Duration(milliseconds: 90));
      expect(chartAnimation.value, greaterThan(0));
      expect(chartAnimation.value, lessThan(1));
      if (width >= 840) {
        expect(find.text(fmtCurrency(8000)), findsWidgets);
        expect(find.text('Account value'), findsOneWidget);
      } else {
        expect(
          tester
              .widget<Text>(find.byKey(const Key('portfolio-total-value')))
              .data,
          fmtCurrency(10000),
        );
        expect(find.text('Account value'), findsOneWidget);
      }
      expect(find.text('40.0%'), findsOneWidget);
      expect(find.text(fmtCurrency(4000)), findsOneWidget);
      slider = tester.widget<Slider>(finder);
      slider.onChanged!(1);
      await tester.pump();
      expect(
        find.text(
          DateFormat('d MMM yyyy').format(portfolioReturnCutoff(-2, now)!),
        ),
        findsOneWidget,
      );
      if (width >= 840) {
        expect(find.text('+10.00%'), findsOneWidget);
        expect(find.text('+${fmtCurrency(1000)}'), findsOneWidget);
      } else {
        expect(find.textContaining('+${fmtCurrency(1000)}'), findsOneWidget);
      }
      expect(
        pieValues(),
        {'VOO': 2000, 'MSFT': 1000, 'OLD': 1000, 'CASH': 7000},
      );
      if (width >= 840) {
        expect(find.text(fmtNativeCurrency(11000, 'USD')), findsWidgets);
      } else {
        expect(
          tester
              .widget<Text>(find.byKey(const Key('portfolio-total-value')))
              .data,
          fmtNativeCurrency(11000, 'USD'),
        );
      }
      expect(find.text('63.6%'), findsOneWidget);
      if (width < 840) {
        final refresh = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        unawaited(refresh.onRefresh());
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump();
          final current = tester.widget<Slider>(finder);
          expect(current.divisions, slider.divisions);
          expect(current.value, 1);
        }
        await tester.pumpAndSettle();
      }
      tester.widget<Slider>(finder).onChanged!(0);
      await tester.pump();
      expect(pieValues(), {'VOO': 5500, 'MSFT': 1000});
      if (width < 840) {
        expect(
          tester
              .widget<Text>(find.byKey(const Key('portfolio-total-value')))
              .data,
          fmtNativeCurrency(12100, 'USD'),
        );
      }
      expect(tester.takeException(), null);
    });
  }

  testWidgets('cold IBKR history loads closed holdings, prices, and cash', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 70);
    final september = portfolioReturnCutoff(11, now)!;
    final october = portfolioReturnCutoff(8, now)!;
    final latest = portfolioReturnCutoff(10, now)!;
    final historyDates = <DateTime>{
      start,
      september,
      october,
      latest,
      for (final period in portfolioFortnightlyPeriods(now, start).skip(1))
        portfolioReturnCutoff(period, now)!,
    }.toList()
      ..sort();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 14000, currency: 'USD'),
    );
    await accounts.cacheIbkrPerformance(
      'Default',
      IbkrPerformanceSeries(
        period: '1Y',
        measure: 'TWR',
        currency: 'USD',
        startDate: start.subtract(const Duration(days: 3)),
        startNav: 0,
        dates: historyDates,
        nav: [
          for (final date in historyDates)
            date == start
                ? 10000
                : date.isBefore(october)
                    ? 11000
                    : date.isBefore(latest)
                        ? 12000
                        : 13000,
        ],
        returnDates: historyDates,
        returns: [
          for (final date in historyDates)
            date == start
                ? 0.0
                : date.isBefore(october)
                    ? .1
                    : date.isBefore(latest)
                        ? .2
                        : .3,
        ],
      ),
    );
    IbkrTrade trade(String symbol, double quantity, DateTime date) => IbkrTrade(
          symbol: symbol,
          name: symbol,
          currency: 'USD',
          conid: 1,
          quantity: quantity,
          price: 100,
          tradeType: quantity > 0 ? 'open' : 'close',
          tradeDate: date,
          realizedPnl: 0,
          commission: 0,
        );
    final synced = <String>{};
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(
        accounts,
        _portfolioPage(
          ibkrLoader: (_) => pending.future,
          historyTradeLoader: (_) async => IbkrTradeHistory(
            available: true,
            trades: [
              trade('VOO', 10, start.add(const Duration(days: 1))),
              trade('SOLD', 4, start.add(const Duration(days: 1))),
              trade('SOLD', -4, now.subtract(const Duration(days: 20))),
            ],
          ),
          historyCandleSync: (symbol, from, config) async {
            expect(from.isBefore(start), isTrue);
            synced.add(symbol);
            for (final date in historyDates.where((date) => date != start)) {
              await testDatabase
                  .into(testDatabase.candles)
                  .insertOnConflictUpdate(
                    CandlesCompanion.insert(
                      symbol: symbol,
                      date: date,
                      close: Value(symbol == 'VOO' ? 100 : 50),
                      rawCurrency: const Value('USD'),
                    ),
                  );
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(synced, {'VOO', 'SOLD'});
    Map<String, double> pie() => {
          for (final slice in tester
              .widget<MarketDonutChart>(find.byType(MarketDonutChart))
              .slices)
            slice.label: slice.value,
        };
    final slider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    for (final label in ['4W ago', '8W ago', '10W ago']) {
      final index =
          List.generate(slider.max.toInt() + 1, (index) => index).firstWhere(
        (index) =>
            slider.semanticFormatterCallback!(index.toDouble()).contains(label),
      );
      slider.onChanged!(index.toDouble());
      await tester.pumpAndSettle();
      expect(
        pie(),
        label == '10W ago'
            ? {'CASH': 10000.0}
            : {
                'VOO': 1000.0,
                'SOLD': 200.0,
                'CASH': label == '4W ago' ? 10800.0 : 9800.0,
              },
      );
      expect(find.textContaining('history unavailable'), findsNothing);
    }
    expect(tester.takeException(), null);
  });

  testWidgets('cached intraday quotes never change fortnightly slider ticks',
      (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await seedFortnightFixture(accounts);
    final now = DateTime.now();
    final holding = cachedPosition();
    await testDatabase.writeIbkrCache(
      profileId: accounts.activeProfileId,
      kind: 'portfolioIntraday',
      cacheKey: '1D',
      payloadJson: jsonEncode(
        CachedPortfolioIntraday(
          positionsKey: CachedPortfolioIntraday.keyFor([holding]),
          cachedAt: now,
          holdings: {
            holding.symbol: IntradayPortfolioHolding(
              quantity: holding.netShares,
              pricesUsd: {now.subtract(const Duration(hours: 1)): 550},
            ),
          },
        ).toJson(),
      ),
      cachedAt: now,
    );
    final reloaded = testAccountManager();
    await reloaded.init();
    var intradayLoads = 0;
    await tester.pumpWidget(
      app(
        reloaded,
        _portfolioPage(
          intradayData: IntradayMarketData(
            ibkrPortfolioFetch: (_, __) async {
              intradayLoads++;
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.labels, ['Now', '2W', '4W', '6W', '8W', '10W']);
    expect(intradayLoads, 0);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(slider.divisions, 5);
    expect(slider.semanticFormatterCallback!(1), contains('2W ago'));
    expect(tester.takeException(), null);
  });

  testWidgets('cold start displays fully cached periods while IBKR hangs',
      (tester) async {
    await seedTestSqlite({});
    final initial = await configuredAccounts();
    final now = DateTime.now();
    final earliest = DateTime(now.year, now.month - 3, now.day - 10);
    final dates = <DateTime>{
      earliest,
      for (var period = 1; period < firstIntradayPeriod; period++)
        if (portfolioReturnCutoff(period, now)!.isAfter(earliest))
          portfolioReturnCutoff(period, now)!,
      for (final period in portfolioFortnightlyPeriods(now, earliest).skip(1))
        portfolioReturnCutoff(period, now)!,
      DateTime(now.year, now.month, now.day),
    }.toList()
      ..sort();
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: earliest,
      startNav: 6500,
      dates: dates,
      nav: [for (final _ in dates) 6500],
      returnDates: dates,
      returns: [for (final _ in dates) 0.0],
    );
    await initial.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 6500, currency: 'USD'),
      netLiquidationUsd: 6500,
    );
    await initial.cacheIbkrPerformance('Default', performance);
    await initial.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    for (final date in dates) {
      await testDatabase.into(testDatabase.candles).insertOnConflictUpdate(
            CandlesCompanion.insert(
              symbol: 'VOO',
              date: date,
              close: const Value(550),
              rawCurrency: const Value('USD'),
            ),
          );
    }
    // Simulate a restart with an old-but-complete local history while its
    // broker performance and trade history requests never return.
    final staleAt = DateTime(2000);
    final profileId = (await testDatabase.readProfileByName('Default'))!.id;
    await testDatabase.writeIbkrCache(
      profileId: profileId,
      kind: 'performance',
      cacheKey: '1Y',
      payloadJson: jsonEncode(
        CachedIbkrPerformanceData(
          series: performance,
          cachedAt: staleAt,
        ).toJson(),
      ),
      cachedAt: staleAt,
    );
    await testDatabase.writeIbkrCache(
      profileId: profileId,
      kind: 'trades',
      cacheKey: 'history',
      payloadJson: jsonEncode(
        CachedIbkrTradeHistoryData(
          history: const IbkrTradeHistory(available: true, trades: []),
          cachedAt: staleAt,
        ).toJson(),
      ),
      cachedAt: staleAt,
    );
    final reloaded = testAccountManager();
    await reloaded.init();
    final stalledPerformance = Completer<IbkrPerformanceSeries>();
    final stalledTrades = Completer<IbkrTradeHistory>();
    final stalledSnapshot = Completer<IbkrPortfolioSnapshot>();
    var performanceLoads = 0;
    var tradeLoads = 0;
    addTearDown(() {
      if (!stalledPerformance.isCompleted)
        stalledPerformance.complete(performance);
      if (!stalledTrades.isCompleted) {
        stalledTrades
            .complete(const IbkrTradeHistory(available: true, trades: []));
      }
      if (!stalledSnapshot.isCompleted) {
        stalledSnapshot.complete(snapshotFor('test', 'VOO'));
      }
    });
    await tester.pumpWidget(
      app(
        reloaded,
        _portfolioPage(
          ibkrLoader: (_) => stalledSnapshot.future,
          ibkrPerformanceLoader: (_, __) {
            performanceLoads++;
            return stalledPerformance.future;
          },
          historyTradeLoader: (_) {
            tradeLoads++;
            return stalledTrades.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(performanceLoads, 1);
    expect(tradeLoads, 1);
    expect(picker.loading, isFalse);
    expect(picker.labels.length, greaterThan(4));
    expect(find.text('VOO'), findsWidgets);
    expect(tester.takeException(), null);
    stalledPerformance.complete(performance);
    stalledTrades.complete(const IbkrTradeHistory(available: true, trades: []));
    stalledSnapshot.complete(snapshotFor('test', 'VOO'));
    await tester.pumpAndSettle();
  });

  testWidgets('missing cached prices retain fortnight stops until repaired',
      (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    final now = DateTime.now();
    final earliest = DateTime(now.year, now.month - 3, now.day - 10);
    final missingDate = portfolioReturnCutoff(-2, now)!; // 2W
    final dates = <DateTime>{
      earliest,
      for (var period = 1; period < firstIntradayPeriod; period++)
        if (portfolioReturnCutoff(period, now)!.isAfter(earliest))
          portfolioReturnCutoff(period, now)!,
      for (final period in portfolioFortnightlyPeriods(now, earliest).skip(1))
        portfolioReturnCutoff(period, now)!,
      DateTime(now.year, now.month, now.day),
    }.toList()
      ..sort();
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: earliest,
      startNav: 6500,
      dates: dates,
      nav: [for (final _ in dates) 6500],
      returnDates: dates,
      returns: [for (final _ in dates) 0.0],
    );
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 6500, currency: 'USD'),
      netLiquidationUsd: 6500,
    );
    await accounts.cacheIbkrPerformance('Default', performance);
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    for (final date in dates.where((date) => date != missingDate)) {
      await testDatabase.into(testDatabase.candles).insertOnConflictUpdate(
            CandlesCompanion.insert(
              symbol: 'VOO',
              date: date,
              close: const Value(550),
              rawCurrency: const Value('USD'),
            ),
          );
    }
    await testDatabase.writeIbkrCache(
      profileId: accounts.activeProfileId,
      kind: 'portfolioPeriods',
      cacheKey: 'complete',
      payloadJson: jsonEncode({
        'version': 1,
        'signature': portfolioHistoryCacheSignature(
          positions: accounts.portfolioCacheFor('Default')!.positions,
          trades: accounts.ibkrTradeHistoryCacheFor('Default'),
          performance: accounts.ibkrPerformanceCacheFor('Default', '1Y'),
        ),
        'periods': [0, 7, 9, 10, 11, 12],
      }),
      cachedAt: DateTime.now(),
    );
    final stalledBackfill = Completer<void>();
    var backfills = 0;
    await tester.pumpWidget(
      app(
        accounts,
        _portfolioPage(
          historyCandleSync: (symbol, from, config) async {
            backfills++;
            await stalledBackfill.future;
            await testDatabase
                .into(testDatabase.candles)
                .insertOnConflictUpdate(
                  CandlesCompanion.insert(
                    symbol: symbol,
                    date: missingDate,
                    close: const Value(550),
                    rawCurrency: const Value('USD'),
                  ),
                );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(backfills, greaterThan(0));
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.loading, isTrue);
    expect(picker.labels, containsAll(['Now', '2W', '4W']));
    final waitingSlider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    waitingSlider.onChanged!(1);
    await tester.pump();
    expect(
      find.textContaining('Historical data could not be reconstructed'),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
    stalledBackfill.complete();
    await tester.pumpAndSettle();
    final completed = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(completed.loading, isFalse);
    expect(completed.labels, contains('2W'));
    expect(find.byType(MarketDonutChart), findsOneWidget);
    expect(
      find.textContaining('Historical data could not be reconstructed'),
      findsNothing,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('missing intraday quotes cannot hide fortnightly stops',
      (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await seedFortnightFixture(accounts, days: 84);
    var intradayLoads = 0;
    await tester.pumpWidget(
      app(
        accounts,
        _portfolioPage(
          intradayData: IntradayMarketData(
            ibkrPortfolioFetch: (_, __) async {
              intradayLoads++;
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.loading, isFalse);
    expect(picker.labels, ['Now', '2W', '4W', '6W', '8W', '10W', '12W']);
    expect(intradayLoads, 0);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(slider.divisions, 6);
    for (var index = 1; index <= slider.max; index++) {
      expect(
        slider.semanticFormatterCallback!(index.toDouble()),
        contains('${index * 2}W ago'),
      );
    }
    expect(tester.takeException(), null);
  });

  testWidgets('partial cached IBKR periods stay loading during trade refresh', (
    tester,
  ) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 70);
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 121, currency: 'USD'),
    );
    final holding = cachedPosition();
    await accounts.cacheIbkrTradeHistory(
      'Default',
      IbkrTradeHistory(
        available: true,
        trades: [
          IbkrTrade(
            symbol: holding.symbol,
            name: holding.name,
            currency: 'USD',
            conid: 1,
            quantity: holding.netShares,
            price: holding.avgCost,
            tradeType: 'open',
            tradeDate: start.add(const Duration(days: 10)),
            realizedPnl: 0,
            commission: 0,
          ),
        ],
      ),
    );
    await accounts.cacheIbkrPerformance(
      'Default',
      IbkrPerformanceSeries(
        period: '1Y',
        measure: 'TWR',
        currency: 'USD',
        startDate: start.subtract(const Duration(days: 3)),
        startNav: 0,
        dates: [start, portfolioReturnCutoff(10, now)!],
        nav: const [100, 121],
        returnDates: [start, portfolioReturnCutoff(10, now)!],
        returns: const [0, .21],
      ),
    );
    await testDatabase.into(testDatabase.candles).insert(
          CandlesCompanion.insert(
            symbol: holding.symbol,
            date: portfolioReturnCutoff(10, now)!,
            close: const Value(10),
            rawCurrency: const Value('USD'),
          ),
        );
    final brokerHistory = accounts.ibkrTradeHistoryCacheFor('Default')!;
    final expiredAt = DateTime(2000);
    await testDatabase.writeIbkrCache(
      profileId: (await testDatabase.readProfileByName('Default'))!.id,
      kind: 'trades',
      cacheKey: 'history',
      payloadJson: jsonEncode(
        CachedIbkrTradeHistoryData(
          history: brokerHistory,
          cachedAt: expiredAt,
        ).toJson(),
      ),
      cachedAt: expiredAt,
    );
    final reloaded = testAccountManager();
    await reloaded.init();
    final pending = Completer<IbkrPortfolioSnapshot>();
    final tradeRefresh = Completer<IbkrTradeHistory>();
    var tradeLoads = 0;
    await tester.pumpWidget(
      app(
        reloaded,
        _portfolioPage(
          ibkrLoader: (_) => pending.future,
          historyTradeLoader: (_) {
            tradeLoads++;
            return tradeRefresh.future;
          },
        ),
      ),
    );
    // Keep pending network calls unresolved; a looping animation cannot settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(tradeLoads, 1);
    final loadingPicker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(loadingPicker.loading, isTrue);
    expect(loadingPicker.labels, contains('2W'));
    expect(find.text('PRESENT'), findsOneWidget);
    final waitingSlider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(waitingSlider.onChanged, isNot(null));
    expect(waitingSlider.divisions, greaterThan(0));
    tradeRefresh.complete(brokerHistory);
    await tester.pumpAndSettle();
    final fullPicker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(fullPicker.loading, isFalse);
    expect(find.textContaining('LOADING HISTORY'), findsNothing);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(slider.semanticFormatterCallback!(1), contains('2W ago'));
    expect(
      slider.semanticFormatterCallback!(slider.max),
      contains('${slider.max.toInt() * 2}W ago'),
    );
    slider.onChanged!(slider.max);
    await tester.pump();
    expect(
      find.text(
        DateFormat('d MMM yyyy').format(start),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<MarketDonutChart>(find.byType(MarketDonutChart))
          .slices
          .single
          .label,
      'CASH',
    );
    expect(find.text('10W AGO'), findsOneWidget);
    expect(tester.takeException(), null);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('cached IBKR values reconstruct every fortnightly date',
      (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await seedFortnightFixture(accounts, days: 70);
    final reloaded = testAccountManager();
    await reloaded.init();
    final pending = Completer<IbkrPortfolioSnapshot>();
    await tester.pumpWidget(
      app(
        reloaded,
        _portfolioPage(
          ibkrLoader: (_) => pending.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.labels, ['Now', '2W', '4W', '6W', '8W', '10W']);
    final finder = find.byKey(const Key('portfolio-return-period'));
    for (var index = 1; index < picker.labels.length; index++) {
      tester.widget<Slider>(finder).onChanged!(index.toDouble());
      await tester.pumpAndSettle();
      expect(find.byType(MarketDonutChart), findsOneWidget);
      expect(find.textContaining('Historical data could not'), findsNothing);
      expect(find.text('No holdings on this date'), findsNothing);
      expect(tester.takeException(), null);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(snapshotFor('test', 'VOO'));
  });

  testWidgets('longer account histories retain exact fortnightly increments',
      (tester) async {
    await seedTestSqlite({});
    final accounts = await configuredAccounts();
    await seedFortnightFixture(accounts, days: 100);
    await tester.pumpWidget(app(accounts, _portfolioPage()));
    await tester.pumpAndSettle();
    final picker = tester.widget<PortfolioPeriodPicker>(
      find.byType(PortfolioPeriodPicker),
    );
    expect(picker.labels, [
      'Now',
      '2W',
      '4W',
      '6W',
      '8W',
      '10W',
      '12W',
      '14W',
    ]);
    final finder = find.byKey(const Key('portfolio-return-period'));
    final slider = tester.widget<Slider>(finder);
    expect(slider.divisions, 7);
    for (var index = 0; index <= slider.max; index++) {
      slider.onChanged!(index.toDouble());
      await tester.pumpAndSettle();
      expect(find.byType(MarketDonutChart), findsOneWidget);
      expect(find.textContaining('Historical data could not'), findsNothing);
      expect(tester.takeException(), null);
    }
  });

  testWidgets('desktop portfolio summary cards keep readable widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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

    expect(find.byKey(const Key('desktop-portfolio-metrics')), findsOneWidget);
    final periodSlider = tester.widget<Slider>(
      find.byKey(const Key('portfolio-return-period')),
    );
    expect(periodSlider.value, 0);
    expect(
      periodSlider.semanticFormatterCallback!(0),
      'Now, current allocation',
    );

    expect(
      (tester.getTopLeft(find.text('Account value')).dy -
              tester.getTopLeft(find.text('Stock value')).dy)
          .abs(),
      lessThan(24),
    );
    expect(
      tester.getTopLeft(find.text('Positions')).dy,
      greaterThan(tester.getTopLeft(find.text('Account value')).dy),
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Open stock positions'))
          .didExceedMaxLines,
      false,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('portfolio reflows allocation at compact desktop widths', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('desktop-allocation-compact')), findsOneWidget);
    final subtitleBottom = tester.getBottomLeft(find.text('Allocation')).dy;
    final compactPieFinder = find.byType(MarketDonutChart).first;
    final pieTop = tester.getTopLeft(compactPieFinder).dy;
    expect(pieTop - subtitleBottom, greaterThanOrEqualTo(28));
    final compactPie = tester.widget<MarketDonutChart>(compactPieFinder);
    expect(compactPie.centerSpaceRadius, 48);
    expect(compactPie.radius, 54);
    expect(compactPie.selectedRadius, 60);
    expect(tester.takeException(), null);
  });

  testWidgets('portfolio handles short compact desktop heights', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('desktop-allocation-compact')), findsOneWidget);
    expect(find.byType(MarketDonutChart), findsOneWidget);
    expect(find.text('VOO'), findsNWidgets(2));
    expect(tester.takeException(), null);
  });

  testWidgets('wide portfolio shows currency and CSV actions inline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'visibleCurrencies': ['NZD', 'USD'],
      'displayCurrency': 'NZD',
    });
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
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('desktop-portfolio-export')), findsOneWidget);
    expect(find.byKey(const Key('desktop-portfolio-share')), findsOneWidget);
    expect(find.byKey(const Key('portfolio-currency-menu')), findsNothing);
    final currencies = find.byKey(const Key('portfolio-currency-buttons'));
    expect(currencies, findsOneWidget);
    await tester.tap(
      find.descendant(of: currencies, matching: find.text('USD')),
    );
    await tester.pump();
    final selector = tester.widget<SegmentedButton<String>>(
      find.descendant(
        of: currencies,
        matching: find.byType(SegmentedButton<String>),
      ),
    );
    expect(selector.selected, {'USD'});
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), null);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'Android share CSV ${fails ? 'shows errors' : 'passes a named file'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(700, 900);
        final temp = Directory.systemTemp.createTempSync('market-monk-share-');
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        final calls = <ShareParams>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(paths, (call) async {
          if (call.method == 'getTemporaryDirectory') return temp.path;
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(paths, null);
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          temp.deleteSync(recursive: true);
        });

        await seedTestSqlite({});
        final accounts = await configuredAccounts();
        await accounts.cachePortfolio(
          'Default',
          [
            cachedPosition(name: 'Vanguard, "Special"\nETF'),
          ],
          const IbkrAccountValue(value: 5500, currency: 'USD'),
        );
        final pending = Completer<IbkrPortfolioSnapshot>();
        await tester.pumpWidget(
          app(
            accounts,
            _portfolioPage(
              ibkrLoader: (_) => pending.future,
              shareFile: (params) async {
                calls.add(params);
                if (fails) throw PlatformException(code: 'share-failed');
                return ShareResult.unavailable;
              },
              writeShareFile: (file, data) async {
                file.writeAsBytesSync(data, flush: true);
              },
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('portfolio-profile-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share CSV'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;

        expect(calls, hasLength(1));
        final params = calls.single;
        final file = params.files!.single;
        expect(file.path, '${temp.path}/positions_Default.csv');
        expect(file.mimeType, 'text/csv');
        expect(params.title, 'Share CSV');
        final csv = File(file.path).readAsStringSync();
        expect(csv, contains('Symbol,Name,Shares,Avg Cost'));
        expect(csv, contains('VOO'));
        final rows = Csv(fieldDelimiter: ',').decode(csv);
        expect(rows[1][0], 'VOO');
        expect(rows[1][1], 'Vanguard, "Special"\nETF');
        expect(rows[1][2], '10.000000');
        expect(csv.endsWith('\n'), isTrue);
        expect(
          find.text('Couldn’t share CSV'),
          fails ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), null);
      },
    );
  }

  for (final (platform, size, shareSupported) in [
    (TargetPlatform.linux, const Size(1200, 900), false),
    (TargetPlatform.windows, const Size(1200, 900), true),
    (TargetPlatform.linux, const Size(700, 900), false),
    (TargetPlatform.android, const Size(700, 900), true),
  ]) {
    testWidgets('portfolio CSV actions for $platform at ${size.width}px', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
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

      await tester.tap(find.byKey(const Key('portfolio-profile-picker')));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('Export CSV'), findsOneWidget);
      expect(
        find.text('Share CSV'),
        shareSupported ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), null);
    });
  }
}
