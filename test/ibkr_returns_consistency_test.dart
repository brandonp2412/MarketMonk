import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Position position({double realized = 0}) => Position(
        symbol: 'VOO',
        name: 'Vanguard',
        nativeCurrency: 'USD',
        netShares: 10,
        avgCost: 500,
        currentPrice: 550,
        firstBuyDate: DateTime(2026, 10, 5),
        lastBuyDate: DateTime(2026, 10, 5),
        brokerRealizedPL: realized,
      );
  Trade trade(DateTime date, double realized, int id) => Trade(
        id: id,
        symbol: 'VOO',
        name: 'Vanguard',
        quantity: -1,
        price: 550,
        tradeType: 'close',
        tradeDate: date,
        realizedPL: realized,
        commission: 1,
      );

  test('realized today uses dated executions, not a zero broker snapshot', () {
    allRatesFromUsd['USD'] = 1;
    final summary = SymbolSummary(
      symbol: 'VOO',
      name: 'Vanguard',
      position: position(),
      trades: [
        trade(DateTime(2026, 10, 8), 125, 1),
        trade(DateTime(2026, 10, 8), -25, 2),
        trade(DateTime(2026, 10, 7), 900, 3),
      ],
    );
    expect(summary.realizedTodayUsd(tradingDate: DateTime(2026, 10, 8)), 100);
    expect(
      summary.realizedTodayUsd(tradingDate: DateTime(2026, 10, 9)),
      isNull,
    );
    expect(
      SymbolSummary(
        symbol: 'VOO',
        name: 'Vanguard',
        position: position(realized: 25),
        trades: const [],
        brokerTradeHistoryAvailable: false,
      ).realizedTodayUsd(tradingDate: DateTime(2026, 10, 8)),
      25,
    );
    expect(
      SymbolSummary(
        symbol: 'VOO',
        name: 'Vanguard',
        position: position(),
        trades: const [],
        brokerTradeHistoryAvailable: false,
      ).realizedTodayUsd(tradingDate: DateTime(2026, 10, 8)),
      isNull,
    );
  });

  testWidgets('1y chart matches portfolio inception cash-out return',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({
      'chartPeriodYears': 1,
      'chartPeriodMonths': 0,
      'chartPeriodDays': 0,
    });
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1;
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
    const nav = IbkrAccountValue(value: 24278.20, currency: 'USD');
    await accounts.cachePortfolio('Default', [position()], nav);
    final performance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: DateTime(2026, 10, 4),
      startNav: 0,
      dates: [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 7),
      ],
      nav: const [3355.69, 3355.196063, 23326.951487],
      cashFlows: const [0, 0, 0],
      returnDates: [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 7),
      ],
      returns: const [0, -0.00014719, -0.00063536],
    );
    await accounts.cacheIbkrPerformance('Default', performance);
    final cashOut = calculateIbkrCashOutPnl(performance, nav);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsState(
              localCurrencyDetector: () async => 'USD',
            ),
          ),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChartsPage(isActive: false)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final expectedReturn = cashOut.percent!.toStringAsFixed(2);
    expect(
      find.text('+$expectedReturn% · Total P/L'),
      findsOneWidget,
    );
    expect(find.text(r'+$939.36'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
