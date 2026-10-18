import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart' as app;
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Linux charts display estimates from cached real IBKR NAV and live prices',
      (tester) async {
    final settings = SettingsState();
    await settings.initialized;
    final accounts = app.AccountManager();
    await accounts.init();
    expect(accounts.accounts, containsAll(['Default', 'IBKR Bot']));
    for (final name in accounts.accounts) {
      expect(accounts.ibkrConfigFor(name).isConfigured, isTrue);
      expect(accounts.portfolioCacheFor(name)?.positions, isNotEmpty);
      debugPrint(
        'E2E $name broker as-of: ${accounts.portfolioCacheFor(name)?.asOfDate}',
      );
    }

    final namesByUrl = {
      for (final name in accounts.accounts)
        accounts.ibkrConfigFor(name).baseUrl: name,
    };
    final historicalPortfolios = {
      for (final name in accounts.accounts)
        name: accounts.portfolioCacheFor(name)!,
    };
    final historicalReturns = {
      for (final name in accounts.accounts)
        name: accounts.ibkrPerformanceCacheFor(name, '1Y')!,
    };
    Future<IbkrPortfolioSnapshot> recordedSnapshot(
      IbkrAccountConfig config,
    ) async {
      final name = namesByUrl[config.baseUrl]!;
      final cached = historicalPortfolios[name]!;
      return IbkrPortfolioSnapshot(
        account: name,
        asOfDate: cached.asOfDate,
        positions: [
          for (final position in cached.positions)
            IbkrPosition(
              symbol: position.symbol,
              securityType: 'STK',
              currency: position.nativeCurrency,
              exchange: '',
              conid: 0,
              quantity: position.netShares,
              marketPrice: position.currentPrice,
              marketValue: position.brokerMarketValue,
              averageCost: position.avgCost,
              unrealizedPnl: position.brokerUnrealizedPL,
              realizedPnl: position.brokerRealizedPL,
            ),
        ],
        summary: {
          'netliquidation': {
            'value': cached.netLiquidation?.value,
            'currency': cached.netLiquidation?.currency,
          },
          'netliquidationbycurrency:usd': {
            'value': cached.netLiquidationUsd,
            'currency': 'USD',
          },
        },
        ledger: const {},
      );
    }

    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: RepaintBoundary(
            key: screenshotKey,
            child: Scaffold(
              body: ChartsPage(
                ibkrLoader: recordedSnapshot,
                ibkrPerformanceLoader: (config, _) async =>
                    historicalReturns[namesByUrl[config.baseUrl]]!,
              ),
            ),
          ),
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final chartFinder = find.byType(MarketLineChart);
      if (chartFinder.evaluate().isNotEmpty) {
        final chart = tester.widget<MarketLineChart>(chartFinder.first);
        final names = chart.series.map((s) => s.name).toSet();
        if (names.containsAll(['Default', 'IBKR Bot']) &&
            ['Default', 'IBKR Bot'].every(
              (name) => find
                  .descendant(
                    of: find.byKey(Key('chart-account-selector-$name')),
                    matching: find.textContaining('≈'),
                  )
                  .evaluate()
                  .isNotEmpty,
            )) {
          break;
        }
      }
    }
    final chart =
        tester.widget<MarketLineChart>(find.byType(MarketLineChart).first);
    for (final series in chart.series) {
      debugPrint(
        'E2E ${series.name} graph points: ${series.points.length}, latest: ${series.points.last.y}',
      );
    }
    for (final name in ['Default', 'IBKR Bot']) {
      expect(
        chart.series.any((s) => s.name == name && s.points.length > 2),
        isTrue,
      );
    }
    final render = screenshotKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final screenshot = await render.toImage(pixelRatio: 1);
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    final output = Platform.environment['MARKET_MONK_E2E_SCREENSHOT'] ??
        '/tmp/marketmonk-linux-e2e.png';
    await File(output).writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('E2E screenshot saved: $output');
    for (final name in ['Default', 'IBKR Bot']) {
      expect(
        find.descendant(
          of: find.byKey(Key('chart-account-selector-$name')),
          matching: find.textContaining('≈'),
        ),
        findsOneWidget,
        reason: '$name must display an estimated value',
      );
    }
  });
}
