import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IBKR portfolio summary uses whole-account cash-out P/L', (
    tester,
  ) async {
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

    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

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
    await accounts.cachePortfolio(
      'Default',
      [
        Position(
          symbol: 'VOO',
          name: 'VANGUARD S&P 500 ETF',
          nativeCurrency: 'USD',
          netShares: 10,
          avgCost: 500,
          currentPrice: 550,
          firstBuyDate: DateTime(2025),
          lastBuyDate: DateTime(2026),
        ),
      ],
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
        child: const MaterialApp(home: PortfolioPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unrealized P/L'), findsOneWidget);
    expect(find.text(r'+$939.36'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
