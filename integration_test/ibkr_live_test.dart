import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart' as app;
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for expected widget');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for expected widget to disappear');
}

Widget _page({
  required SettingsState settings,
  required app.AccountManager accounts,
  required Widget child,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live IBKR works through settings and portfolio UI',
      (tester) async {
    const definedUrl = String.fromEnvironment('MARKET_MONK_IBKR_E2E_URL');
    const definedToken = String.fromEnvironment('MARKET_MONK_IBKR_E2E_TOKEN');
    final url = definedUrl.isNotEmpty
        ? definedUrl
        : Platform.environment['MARKET_MONK_IBKR_E2E_URL'] ?? '';
    final token = definedToken.isNotEmpty
        ? definedToken
        : Platform.environment['MARKET_MONK_IBKR_E2E_TOKEN'] ?? '';
    expect(url, isNotEmpty, reason: 'MARKET_MONK_IBKR_E2E_URL is required');
    expect(token, isNotEmpty, reason: 'MARKET_MONK_IBKR_E2E_TOKEN is required');

    final liveConfig = IbkrAccountConfig(
      enabled: true,
      baseUrl: url,
      token: token,
    );
    final expected = await IbkrApiClient(liveConfig).fetchPortfolio();
    final stocks = expected.positions
        .where(
          (position) => position.securityType == 'STK' && position.quantity > 0,
        )
        .toList();
    expect(stocks, isNotEmpty);
    final largest = stocks.reduce(
      (a, b) => (a.marketValue ?? 0) >= (b.marketValue ?? 0) ? a : b,
    );
    final alphabeticallyFirst = [...stocks]
      ..sort((a, b) => a.symbol.compareTo(b.symbol));

    app.db = Database.connect(NativeDatabase.memory());
    final settings = SettingsState();
    await settings.initialized;
    final accounts = app.AccountManager();
    await accounts.init();

    await tester.pumpWidget(
      _page(
        settings: settings,
        accounts: accounts,
        child: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Interactive Brokers'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Interactive Brokers'));
    await tester.pumpAndSettle();

    expect(find.text('Interactive Brokers — Default'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), url);
    await tester.enterText(fields.at(1), token);
    final enabledSwitch =
        find.widgetWithText(SwitchListTile, 'Use IBKR portfolio data');
    expect(enabledSwitch, findsOneWidget);
    if (!tester.widget<SwitchListTile>(enabledSwitch).value) {
      await tester.tap(enabledSwitch);
      await tester.pump();
    }

    await tester.tap(find.text('Test'));
    await _pumpUntil(tester, find.text('Connected to IBKR'));

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpUntilGone(tester, find.text('Interactive Brokers — Default'));
    expect(accounts.ibkrConfigFor().enabled, isTrue);
    expect(accounts.ibkrConfigFor().baseUrl, url);

    await tester.pumpWidget(
      _page(
        settings: settings,
        accounts: accounts,
        child: const app.MyHomePage(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('PortfolioPage')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PortfolioPage), findsOneWidget);
    await _pumpUntil(tester, find.text(largest.symbol));

    await tester.tap(find.byKey(const Key('HoldingsPage')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HoldingsPage), findsOneWidget);
    await _pumpUntil(tester, find.text(alphabeticallyFirst.first.symbol));
  });
}
