import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';
import 'test_log_support.dart';

http.Response _prices(double first, {String currency = 'GBp'}) => http.Response(
      jsonEncode({
        'chart': {
          'result': [
            {
              'meta': {'currency': currency},
              'timestamp': [1791552600, 1791552660, 1791552720],
              'indicators': {
                'quote': [
                  {
                    'open': [first, first + 1, first + 2],
                    'high': [first, first + 1, first + 2],
                    'low': [first, first + 1, first + 2],
                    'close': [first, first + 1, first + 2],
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
      'chartPeriodDays': 1,
      'exchangeRate_GBP': 0.75,
    });
    allRatesFromUsd.remove('GBP');
    final accounts = testAccountManager();
    await accounts.init();
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
              initialSymbol: 'VOD.L',
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
