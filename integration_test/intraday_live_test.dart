import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

import '../test/sqlite_test_support.dart';

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('Timed out waiting for live intraday chart');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live Linux stock and favorite charts render intraday bars',
      (tester) async {
    await seedTestSqlite({
      'chartPeriodYears': 0,
      'chartPeriodMonths': 0,
      'chartPeriodDays': 5,
      'favoriteStocks': ['SPY'],
      'showMarketClosed': false,
    });
    final accounts = testAccountManager();
    await accounts.init();
    final settings = SettingsState(localCurrencyDetector: () async => 'USD');
    await settings.initialized;
    final boundaryKey = GlobalKey();
    final output = Directory(
      const String.fromEnvironment(
        'MARKET_MONK_E2E_OUTPUT',
        defaultValue: '/tmp/market-monk-intraday-e2e',
      ),
    );
    await output.create(recursive: true);

    Future<void> mount({String? symbol}) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: accounts),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.linux),
              home: Scaffold(
                body: ChartsPage(key: UniqueKey(), initialSymbol: symbol),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    MarketLineChart? chart() {
      final found = find.byType(MarketLineChart);
      return found.evaluate().isEmpty
          ? null
          : tester.widget<MarketLineChart>(found.first);
    }

    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 500));
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File('${output.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    }

    if (!const bool.fromEnvironment('MARKET_MONK_PORTFOLIO_ONLY')) {
      await mount();
      await _waitFor(tester, () => find.text('SPY').evaluate().isNotEmpty);
      await tester.tap(find.text('SPY'));
      await _waitFor(
        tester,
        () =>
            chart()?.series.any(
                  (series) => series.name == 'SPY' && series.points.length > 20,
                ) ??
            false,
      );
      final favorite = chart()!.series.single;
      expect(favorite.points.length, greaterThan(20));
      expect(chart()!.xLabels.any((label) => label.contains(':')), isTrue);
      debugPrint(
        'LIVE Yahoo favorite 5d rendered ${favorite.points.length} points',
      );
      await capture('yahoo-favorite-5d');

      await tester.tap(find.text('SPY'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open chart'));
      await _waitFor(
        tester,
        () => find.text('Yahoo · 15 min · Local time').evaluate().isNotEmpty,
      );
      expect(chart()!.series.single.points.length, greaterThan(20));
      debugPrint(
        'LIVE Yahoo stock 5d rendered ${chart()!.series.single.points.length} points',
      );
      await capture('yahoo-stock-5d');
      await tester.tap(find.byKey(const Key('chart-period-1d')));
      await _waitFor(
        tester,
        () => find.text('Yahoo · 1 min · Local time').evaluate().isNotEmpty,
      );
      expect(chart()!.series.single.points.length, greaterThan(20));
      debugPrint(
        'LIVE Yahoo stock 1d rendered ${chart()!.series.single.points.length} points',
      );
      await capture('yahoo-stock-1d');
    }
    const rawConfigs = String.fromEnvironment('MARKET_MONK_LIVE_CONFIGS');
    final configs = rawConfigs.isEmpty ? [] : jsonDecode(rawConfigs) as List;
    if (!const bool.fromEnvironment('MARKET_MONK_PORTFOLIO_ONLY')) {
      for (var index = 0; index < configs.length; index++) {
        final raw = configs[index] as Map<String, dynamic>;
        final config = IbkrAccountConfig(
          enabled: true,
          baseUrl: raw['base_url'] as String,
          token: raw['token'] as String,
        );
        final snapshot = await IbkrApiClient(config).fetchPortfolio();
        final symbol = snapshot.positions
            .firstWhere(
              (position) =>
                  position.securityType == 'STK' && position.quantity > 0,
            )
            .symbol;
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await accounts.setIbkrConfig(accounts.activeAccount, config);
        await mount(symbol: symbol);
        await _waitFor(
          tester,
          () => find.text('IBKR · 1 min · Local time').evaluate().isNotEmpty,
        );
        expect(chart()!.series.single.points.length, greaterThan(20));
        debugPrint(
          'LIVE IBKR account ${index + 1} stock 1d rendered ${chart()!.series.single.points.length} points',
        );
        await capture('ibkr-${index + 1}-stock-1d');
        await tester.tap(find.byKey(const Key('chart-period-5d')));
        await _waitFor(
          tester,
          () => find.text('IBKR · 15 min · Local time').evaluate().isNotEmpty,
        );
        expect(chart()!.series.single.points.length, greaterThan(20));
        debugPrint(
          'LIVE IBKR account ${index + 1} stock 5d rendered ${chart()!.series.single.points.length} points',
        );
        await capture('ibkr-${index + 1}-stock-5d');
        await tester.tap(find.byKey(const Key('chart-period-1d')));
        await _waitFor(
          tester,
          () => find.text('IBKR · 1 min · Local time').evaluate().isNotEmpty,
        );
      }
    }
    if (configs.isNotEmpty) {
      await tester.pumpWidget(const SizedBox());
      for (var index = 0; index < configs.length; index++) {
        final raw = configs[index] as Map<String, dynamic>;
        final name = index == 0 ? 'Default' : 'IBKR account ${index + 1}';
        if (index > 0) await accounts.addAccount(name);
        await accounts.setIbkrConfig(
          name,
          IbkrAccountConfig(
            enabled: true,
            baseUrl: raw['base_url'] as String,
            token: raw['token'] as String,
          ),
        );
      }
      final prefs = await SqliteSettings.getInstance();
      await prefs.setInt('chartPeriodDays', 5);
      final coldLoad = Stopwatch()..start();
      await mount();
      await _waitFor(
        tester,
        () =>
            chart()?.series.length == configs.length &&
            chart()!.series.every((series) => series.points.length > 20),
      );
      for (final series in chart()!.series) {
        debugPrint(
          'LIVE portfolio 5d ${series.name} rendered ${series.points.length} points',
        );
      }
      expect(chart()!.xLabels.first, contains(RegExp(r'\d{2}:\d{2}')));
      debugPrint(
        'LIVE portfolio 5d cold load ${coldLoad.elapsedMilliseconds} ms',
      );
      final fiveDayCounts = {
        for (final series in chart()!.series) series.name: series.points.length,
      };
      await capture('ibkr-portfolio-5d');
      final firstOneDay = Stopwatch()..start();
      await tester.tap(find.byKey(const Key('chart-period-1d')));
      await _waitFor(
        tester,
        () =>
            chart()?.series.length == configs.length &&
            chart()!.series.every((series) => series.points.length > 100),
      );
      for (final series in chart()!.series) {
        debugPrint(
          'LIVE portfolio 1d ${series.name} rendered ${series.points.length} points',
        );
      }
      final oneDayCounts = {
        for (final series in chart()!.series) series.name: series.points.length,
      };
      await capture('ibkr-portfolio-1d');
      debugPrint(
        'LIVE portfolio 1d cold load ${firstOneDay.elapsedMilliseconds} ms',
      );
      int priceRequests() => [
            'market.intradayPortfolio',
            'ibkr.intradayPortfolio',
            'market.intraday',
            'ibkr.intraday',
            'yahoo.intraday',
          ].fold(
            0,
            (sum, category) =>
                sum + backgroundNetworkCoordinator.startedCount(category),
          );
      final requests = priceRequests();
      for (final period in ['5d', '1d']) {
        final switchTime = Stopwatch()..start();
        await tester.tap(find.byKey(Key('chart-period-$period')));
        await tester.pump();
        expect(chart()?.series.length, configs.length);
        expect(
          chart()!.series.every(
                (series) =>
                    series.points.length ==
                    (period == '5d'
                        ? fiveDayCounts
                        : oneDayCounts)[series.name],
              ),
          isTrue,
        );
        expect(find.bySemanticsLabel('Loading portfolio'), findsNothing);
        debugPrint(
          'LIVE cached portfolio $period visible in ${switchTime.elapsedMilliseconds} ms',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(priceRequests(), requests);
        await capture('ibkr-portfolio-$period-cached');
      }
      debugPrint(
        'LIVE cached 5d and 1d switches made zero additional price requests',
      );
    }
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    accounts.dispose();
  });
}
