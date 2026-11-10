import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux IBKR Bot history completes and renders every allocation',
      (tester) async {
    expect(Platform.isLinux, isTrue);
    final path = Platform.environment['MARKET_MONK_E2E_DATABASE'] ??
        '${Platform.environment['HOME']}/.local/share/com.codesail.market_monk/market-monk.unified.sqlite';
    expect(File(path).existsSync(), isTrue);
    final database = Database.connect(NativeDatabase(File(path)));
    setProfileDataDatabaseForTesting(database);
    setMarketDataDatabaseForTesting(database);
    await SqliteSettings.useInstance(SqliteSettings.load(database));
    backgroundNetworkCoordinator.observeAppLifecycle();
    final settings = SettingsState();
    await settings.initialized;
    final accounts = AccountManager();
    await accounts.init();
    await accounts.switchAccount('IBKR Bot');
    expect(accounts.ibkrConfigFor().isConfigured, isTrue);
    final screenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final clock = Stopwatch()..start();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: RepaintBoundary(
          key: screenshotKey,
          child: const MyApp(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final portfolioNav =
        find.byKey(const Key('desktop-PortfolioPage')).hitTestable();
    expect(portfolioNav, findsOneWidget);
    await tester.tap(portfolioNav);
    await tester.pump(const Duration(milliseconds: 300));
    Future<void> screenshot(String name) async {
      final render = screenshotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('/tmp/market-monk-portfolio-$name.png');
      await output.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      debugPrint('E2E screenshot: ${output.path}');
    }

    bool historyReady() {
      final selector = find.byKey(const Key('portfolio-return-period'));
      if (selector.evaluate().isEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty)
        return false;
      final slider = tester.widget<Slider>(selector);
      final labels = [
        for (var index = 0; index <= slider.max.toInt(); index++)
          slider.semanticFormatterCallback!(index.toDouble()),
      ];
      return ['1M ago', '2M ago', 'Inception'].every(
        (label) => labels.any((text) => text.contains(label)),
      );
    }

    var ready = false;
    while (clock.elapsed < const Duration(seconds: 25)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (historyReady()) {
        ready = true;
        break;
      }
    }
    debugPrint('E2E loading ${clock.elapsedMilliseconds}ms; lifecycle '
        '${binding.lifecycleState}; '
        '${backgroundNetworkCoordinator.diagnosticsSummary()}');
    await screenshot('startup');
    expect(
      ready,
      isTrue,
      reason: 'Cached history must finish within 25 seconds',
    );
    expect(tester.takeException(), null);
    if (Platform.environment['MARKET_MONK_E2E_LIVE_BROKER'] == '1') {
      final client = IbkrApiClient(accounts.ibkrConfigFor());
      final snapshot = await client.fetchPortfolio();
      final performance = await client.fetchPerformance('1Y');
      final trades = await client.fetchTradeHistory();
      final intraday = await client.fetchIntradayPortfolio();
      expect(snapshot.positions, isNotEmpty);
      expect(performance.dates, isNotEmpty);
      expect(trades.available, isTrue);
      expect(trades.trades, isNotEmpty);
      expect(intraday, hasLength(snapshot.positions.length));
      final previous = accounts.portfolioCacheFor()!.cachedAt;
      final refresh = find.byTooltip('Refresh').hitTestable();
      expect(refresh, findsOneWidget);
      await tester.tap(refresh);
      final refreshClock = Stopwatch()..start();
      var quietSince = refreshClock.elapsed;
      var completed = false;
      while (refreshClock.elapsed < const Duration(seconds: 90)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (accounts.portfolioCacheFor()!.cachedAt == previous ||
            !historyReady() ||
            backgroundNetworkCoordinator.activeRequestCount > 0) {
          quietSince = refreshClock.elapsed;
        } else if (refreshClock.elapsed - quietSince >=
            const Duration(seconds: 2)) {
          completed = true;
          break;
        }
      }
      debugPrint(
        backgroundNetworkCoordinator.diagnosticsSummary(
          label: 'E2E refresh complete',
        ),
      );
      expect(
        completed,
        isTrue,
        reason: 'The live refresh must finish all requests',
      );
      for (final category in [
        RequestCategory.ibkrHistorical,
        RequestCategory.ibkrPortfolio,
        RequestCategory.ibkrPerformance,
        RequestCategory.ibkrTrades,
        'ibkr.intradayPortfolio',
      ]) {
        expect(
          backgroundNetworkCoordinator.failedCount(category),
          0,
          reason: category,
        );
      }
      final refreshed = accounts.portfolioCacheFor()!;
      expect(refreshed.cachedAt.isAfter(previous), isTrue);
      expect(refreshed.netLiquidation!.value, snapshot.netLiquidation!.value);
      expect(refreshed.positions, hasLength(snapshot.positions.length));
      debugPrint(
          'E2E forced live refresh ${refreshClock.elapsedMilliseconds}ms: '
          '${refreshed.positions.length} positions; '
          '${trades.trades.length} trades; '
          '${intraday.length} intraday series; '
          'NAV ${refreshed.netLiquidation!.value} ${refreshed.netLiquidation!.currency}');
      await screenshot('live-refreshed');
      expect(tester.takeException(), null);
    }
    final finder = find.byKey(const Key('portfolio-return-period'));
    for (final label in ['1M ago', '2M ago', 'Inception']) {
      final slider = tester.widget<Slider>(finder);
      final index =
          List.generate(slider.max.toInt() + 1, (index) => index).firstWhere(
        (index) =>
            slider.semanticFormatterCallback!(index.toDouble()).contains(label),
      );
      final bounds = tester.getRect(finder);
      final x = bounds.left + 24 + (bounds.width - 48) * index / slider.max;
      await tester.tapAt(Offset(x, bounds.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<Slider>(finder).value, index.toDouble());
      final chart =
          tester.widget<MarketDonutChart>(find.byType(MarketDonutChart));
      final allocations = {
        for (final slice in chart.slices) slice.label: slice.value,
      };
      debugPrint('E2E $label: $allocations');
      expect(allocations['CASH'], greaterThan(0));
      expect(allocations.length, label == 'Inception' ? 1 : greaterThan(1));
      expect(find.textContaining('history unavailable'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await screenshot(
        label == 'Inception' ? 'inception' : label.substring(0, 2),
      );
      expect(tester.takeException(), null);
    }
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), null);
  });
}
