import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';
import 'test_log_support.dart';

http.Response _prices(
  double first, {
  String currency = 'GBp',
  int count = 3,
  int intervalSeconds = 60,
}) =>
    http.Response(
      jsonEncode({
        'chart': {
          'result': [
            {
              'meta': {'currency': currency},
              'timestamp': [
                for (var i = 0; i < count; i++)
                  1791552600 + i * intervalSeconds,
              ],
              'indicators': {
                'quote': [
                  {
                    'open': [for (var i = 0; i < count; i++) first + i],
                    'high': [for (var i = 0; i < count; i++) first + i],
                    'low': [for (var i = 0; i < count; i++) first + i],
                    'close': [for (var i = 0; i < count; i++) first + i],
                  }
                ],
              },
            }
          ],
          'error': null,
        },
      }),
      200,
    );

void main() {
  setUp(silenceTalkerForTest);

  Future<void> mountChart(
    WidgetTester tester,
    IntradayMarketData loader, {
    bool active = true,
    String? initialSymbol = 'VOD.L',
    List<String> favorites = const [],
    int days = 1,
    Future<void> Function(AccountManager)? configureAccounts,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'chartPeriodYears': 0,
      'chartPeriodMonths': 0,
      'chartPeriodDays': days,
      'favoriteStocks': favorites,
      'exchangeRate_GBP': 0.75,
    });
    allRatesFromUsd.remove('GBP');
    final accounts = testAccountManager();
    await accounts.init();
    await configureAccounts?.call(accounts);
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
              initialSymbol: initialSymbol,
              intradayData: loader,
              isActive: active,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
      '1d renders all minute prices and local times without daily writes',
      (tester) async {
    final loader = IntradayMarketData(yahooGet: (_) async => _prices(100));
    await mountChart(tester, loader);
    await tester.pumpAndSettle();
    final ticker = tester.widget<TickerLine>(find.byType(TickerLine));
    expect(ticker.intraday, isTrue);
    expect(ticker.nativeCurrency, 'GBP');
    expect(ticker.spots.map((point) => point.y), [1, 1.01, 1.02]);
    expect(
      ticker.dates.first,
      DateTime.fromMillisecondsSinceEpoch(1791552600000, isUtc: true).toLocal(),
    );
    final chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.xLabels.first, contains(RegExp(r'\d{2}:\d{2}')));
    expect(find.text('Yahoo · 1 min · Local time'), findsOneWidget);
    expect(await testDatabase.select(testDatabase.candles).get(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late 1d response cannot replace the selected 5d chart',
      (tester) async {
    final minute = Completer<http.Response>();
    final loader = IntradayMarketData(
      yahooGet: (uri) async {
        return uri.queryParameters['range'] == '1d'
            ? minute.future
            : _prices(200, currency: 'USD');
      },
    );
    await mountChart(tester, loader);
    await tester.tap(find.byKey(const Key('chart-period-5d')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TickerLine>(find.byType(TickerLine)).spots.first.y,
      200,
    );
    minute.complete(_prices(100));
    await tester.pumpAndSettle();
    final ticker = tester.widget<TickerLine>(find.byType(TickerLine));
    expect(ticker.spots.first.y, 200);
    expect(ticker.nativeCurrency, 'USD');
    expect(find.text('Yahoo · 15 min · Local time'), findsOneWidget);
  });

  testWidgets('unavailable intraday data shows a retryable error',
      (tester) async {
    var calls = 0;
    final loader = IntradayMarketData(
      yahooGet: (_) async {
        calls++;
        return calls == 1 ? http.Response('rate limited', 429) : _prices(100);
      },
    );
    await mountChart(tester, loader);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Yahoo intraday returned HTTP 429'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byType(TickerLine), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('favorite 5d chart preserves all intraday observations',
      (tester) async {
    final loader = IntradayMarketData(
      yahooGet: (_) async => _prices(
        100,
        currency: 'USD',
        count: 12,
        intervalSeconds: 900,
      ),
    );
    await mountChart(
      tester,
      loader,
      initialSymbol: null,
      favorites: ['AAPL'],
      days: 5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL'));
    await tester.pumpAndSettle();
    final chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.series.single.name, 'AAPL');
    expect(chart.series.single.points, hasLength(12));
    expect(chart.series.single.points.first.y, 0);
    expect(chart.series.single.points.last.y, closeTo(11, 1e-8));
    expect(chart.xLabels.first, contains(RegExp(r'\d{2}:\d{2}')));
  });

  testWidgets('portfolio 5d weights every holding and offers intraday 1d',
      (tester) async {
    var requests = 0;
    var now = DateTime.utc(2026, 10, 10);
    final loader = IntradayMarketData(
      now: () => now,
      yahooGet: (uri) async {
        requests++;
        return _prices(
          uri.path.endsWith('AAPL') ? 100 : 50,
          currency: 'USD',
          count: uri.queryParameters['range'] == '5d' ? 12 : 3,
          intervalSeconds: uri.queryParameters['range'] == '5d' ? 900 : 60,
        );
      },
    );
    await mountChart(
      tester,
      loader,
      initialSymbol: null,
      days: 5,
      configureAccounts: (accounts) async {
        await accounts.setIbkrConfig(
          'Default',
          const IbkrAccountConfig(enabled: true),
        );
        await accounts.cachePortfolio(
          'Default',
          [
            for (final entry in {'AAPL': 2.0, 'MSFT': 3.0}.entries)
              Position(
                symbol: entry.key,
                name: entry.key,
                nativeCurrency: 'USD',
                netShares: entry.value,
                avgCost: 50,
                currentPrice: 100,
                firstBuyDate: DateTime(2026),
                lastBuyDate: DateTime(2026),
              ),
          ],
          const IbkrAccountValue(value: 1000, currency: 'USD'),
        );
      },
    );
    await tester.pumpAndSettle();
    var chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.series.single.name, 'Default');
    expect(chart.series.single.points, hasLength(12));
    expect(chart.series.single.points.first.y, 945);
    expect(chart.series.single.points.last.y, 1000);
    expect(chart.xLabels.first, contains(RegExp(r'\d{2}:\d{2}')));
    expect(find.textContaining('TWR'), findsNothing);
    await tester.tap(find.byKey(const Key('chart-period-1d')));
    await tester.pumpAndSettle();
    chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.series.single.points, hasLength(3));
    expect(chart.series.single.points.first.y, 990);
    expect(chart.series.single.points.last.y, 1000);
    expect(requests, 4);
    now = now.add(const Duration(minutes: 10));
    await tester.tap(find.byKey(const Key('chart-period-5d')));
    await tester.pump();
    chart = tester.widget<MarketLineChart>(find.byType(MarketLineChart));
    expect(chart.series.single.points, hasLength(12));
    expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);
    await tester.pumpAndSettle();
    expect(requests, 4);
    await tester.tap(find.byKey(const Key('chart-period-1d')));
    await tester.pumpAndSettle();
    expect(requests, 4);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(requests, 6);
  });

  testWidgets('inactive charts do not request intraday bars', (tester) async {
    var calls = 0;
    final loader = IntradayMarketData(
      yahooGet: (_) async {
        calls++;
        return _prices(100);
      },
    );
    await mountChart(tester, loader, active: false);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
