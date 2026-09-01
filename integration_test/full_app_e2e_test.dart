import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/main.dart' as app;
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

Future<void> _waitForTradeCount(int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final trades = await app.db.select(app.db.trades).get();
    if (trades.length == count) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for $count trades');
}

Future<void> _seedCandlesIfMissing(String symbol, double price) async {
  final existing = await (app.db.select(app.db.candles)
        ..where((row) => row.symbol.equals(symbol))
        ..limit(1))
      .getSingleOrNull();
  if (existing != null) return;

  final today = DateTime.now();
  await app.db.batch((batch) {
    batch.insertAll(
      app.db.candles,
      List.generate(40, (index) {
        final close = price + index * 0.25;
        return CandlesCompanion.insert(
          symbol: symbol,
          date: today.subtract(Duration(days: 39 - index)),
          open: Value(close - 0.2),
          high: Value(close + 0.4),
          low: Value(close - 0.4),
          close: Value(close),
          adjClose: Value(close),
          volume: Value(1000000 + index),
        );
      }),
    );
  });
}

Future<void> _scrollTo(
  WidgetTester tester,
  String text, {
  double delta = 500,
}) async {
  final finder = find.text(text);
  if (finder.evaluate().isNotEmpty) return;
  final settingsScrollable = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: settingsScrollable,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _addLocalTrade(
  WidgetTester tester, {
  required String symbol,
  required String quantity,
  required String price,
  required int expectedTradeCount,
}) async {
  await tester.tap(find.text('Add'));
  await _pumpUntil(tester, find.byType(EditTickerPage));
  await tester.pumpAndSettle();

  final searchInput = find
      .descendant(
        of: find.byType(EditTickerPage),
        matching: find.byType(EditableText),
      )
      .first;
  expect(searchInput, findsOneWidget);
  await tester.enterText(searchInput, symbol);

  final fields = find.descendant(
    of: find.byType(EditTickerPage),
    matching: find.byType(TextField),
  );
  expect(fields, findsNWidgets(4));
  await tester.enterText(fields.at(1), quantity);
  await tester.enterText(fields.at(2), price);

  final saveButton = find.byType(FloatingActionButton).hitTestable();
  expect(saveButton, findsOneWidget);
  await tester.tap(saveButton);
  await _waitForTradeCount(expectedTradeCount);
  await _pumpUntilGone(tester, find.byType(EditTickerPage));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('whole app local-account workflow is functional', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    try {
      await app.db.close();
    } catch (_) {}
    app.db = Database();
    await app.db.delete(app.db.trades).go();
    await app.db.delete(app.db.candles).go();

    final settings = SettingsState();
    await settings.initialized;
    final accounts = app.AccountManager();
    await accounts.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const app.MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChartsPage), findsOneWidget);
    expect(find.byKey(const Key('ChartPage')), findsOneWidget);
    expect(find.byKey(const Key('PortfolioPage')), findsOneWidget);
    expect(find.byKey(const Key('HoldingsPage')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings).first);
    await _pumpUntil(tester, find.byType(SettingsPage));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.theme, ThemeMode.dark);

    final originalSystemColors = settings.systemColors;
    await tester.tap(find.text('System color scheme'));
    await tester.pump();
    expect(settings.systemColors, isNot(originalSystemColors));

    await tester.tap(find.text('Pure black (AMOLED)'));
    await tester.pump();
    expect(settings.pureBlack, isTrue);

    await _scrollTo(tester, 'Curve line graphs');
    await tester.tap(find.text('Curve line graphs'));
    await tester.pump();
    expect(settings.curveLines, isTrue);

    final smoothnessBefore = settings.curveSmoothness;
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    expect(settings.curveSmoothness, isNot(smoothnessBefore));

    await _scrollTo(tester, 'Currencies');
    await tester.tap(find.text('Currencies'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('NZD'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final nzd = find.widgetWithText(CheckboxListTile, 'NZD');
    expect(nzd, findsOneWidget);
    await tester.tap(nzd);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(settings.visibleCurrencies, contains('NZD'));

    await _scrollTo(tester, 'Manage accounts');
    await tester.tap(find.text('Manage accounts'));
    await _pumpUntil(tester, find.byType(AccountsPage));

    await tester.tap(find.text('New account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'E2E Local');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await _pumpUntil(tester, find.text('E2E Local'));
    expect(accounts.accounts, contains('E2E Local'));

    await tester.tap(find.byTooltip('Rename account').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'E2E Local Renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await _pumpUntil(tester, find.text('E2E Local Renamed'));
    expect(accounts.accounts, contains('E2E Local Renamed'));
    expect(accounts.accounts, isNot(contains('E2E Local')));

    await tester.tap(find.text('E2E Local Renamed'));
    await _pumpUntilGone(tester, find.byType(AccountsPage));
    expect(accounts.activeAccount, 'E2E Local Renamed');

    await tester.tap(find.byTooltip('Back'));
    await _pumpUntilGone(tester, find.byType(SettingsPage));

    await tester.tap(find.byIcon(Icons.list_alt).hitTestable().last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HoldingsPage), findsOneWidget);

    await _addLocalTrade(
      tester,
      symbol: 'MSFT',
      quantity: '2',
      price: '100',
      expectedTradeCount: 1,
    );
    if (Platform.isAndroid) await _seedCandlesIfMissing('MSFT', 100);
    await _pumpUntil(tester, find.text('MSFT'));

    await tester.tap(find.text('MSFT').first);
    await _pumpUntil(tester, find.byType(TradeHistoryPage));
    expect(find.text('BUY'), findsOneWidget);

    await tester.longPress(find.text('BUY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit trade'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Trade'), findsOneWidget);
    final editFields = find.descendant(
      of: find.widgetWithText(AlertDialog, 'Edit Trade'),
      matching: find.byType(TextField),
    );
    expect(editFields, findsNWidgets(2));
    await tester.enterText(editFields.at(0), '3');
    await tester.enterText(editFields.at(1), '110');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpUntilGone(tester, find.text('Edit Trade'));

    var storedTrade = (await app.db.select(app.db.trades).get()).single;
    expect(storedTrade.quantity, 3);
    expect(storedTrade.price, 110);

    await tester.tap(find.byTooltip('Back'));
    await _pumpUntil(tester, find.byType(HoldingsPage));

    await tester.tap(find.byIcon(Icons.pie_chart).hitTestable().last);
    await _pumpUntil(tester, find.byType(PortfolioPage));
    await _pumpUntil(tester, find.text('MSFT'));
    final filter = find.descendant(
      of: find.byType(PortfolioPage),
      matching: find.byType(TextField),
    );
    expect(filter, findsOneWidget);
    await tester.enterText(filter, 'ZZZ');
    await tester.pump();
    expect(find.text('MSFT'), findsNothing);
    await tester.enterText(filter, 'MS');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final portfolioMsft = find.descendant(
      of: find.byType(PortfolioPage),
      matching: find.widgetWithText(ListTile, 'MSFT'),
    );
    if (portfolioMsft.evaluate().isEmpty) {
      final portfolioScrollable = find.descendant(
        of: find.byType(PortfolioPage),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.scrollUntilVisible(
        portfolioMsft,
        300,
        scrollable: portfolioScrollable.first,
      );
    }
    expect(portfolioMsft, findsWidgets);

    await tester.tap(find.byIcon(Icons.insights).hitTestable().last);
    await _pumpUntil(tester, find.byType(ChartsPage));
    final chartSearch = find
        .descendant(
          of: find.byType(ChartsPage),
          matching: find.byType(EditableText),
        )
        .first;
    await tester.enterText(chartSearch, 'MSFT');
    await _pumpUntil(tester, find.text('Use "MSFT" anyway'));
    await tester.tap(find.text('Use "MSFT" anyway'));
    await _pumpUntil(
      tester,
      find.byType(TickerLine),
      timeout: const Duration(seconds: 60),
    );
    await _pumpUntil(tester, find.text('Favorite'));
    await tester.tap(find.text('Favorite'));
    await tester.pump();
    expect(
      (await SharedPreferences.getInstance()).getStringList('favoriteStocks'),
      contains('MSFT'),
    );

    for (final period in ['5d', '1m', '10y']) {
      await tester.tap(find.text(period));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pump();
    expect(find.text('MSFT'), findsWidgets);
    await _pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 8),
    );

    await tester.tap(find.byIcon(Icons.list_alt).hitTestable().last);
    await _pumpUntil(tester, find.byType(HoldingsPage));
    await _pumpUntil(tester, find.text('MSFT'));
    await tester.tap(find.text('MSFT').first);
    await _pumpUntil(tester, find.byType(TradeHistoryPage));
    await tester.longPress(find.text('BUY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete trade'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _waitForTradeCount(0);
    await _pumpUntil(tester, find.text('No trade history imported yet'));

    await tester.tap(find.byTooltip('Back'));
    await _pumpUntil(tester, find.byType(HoldingsPage));
    await _addLocalTrade(
      tester,
      symbol: 'AAPL',
      quantity: '1',
      price: '150',
      expectedTradeCount: 1,
    );

    final holdingsSearch = find
        .descendant(
          of: find.byType(HoldingsPage),
          matching: find.byType(EditableText),
        )
        .first;
    final holdingsAapl = find.descendant(
      of: find.byType(HoldingsPage),
      matching: find.text('AAPL'),
    );
    await tester.enterText(holdingsSearch, 'AAPL');
    await _pumpUntil(tester, holdingsAapl);
    await tester.enterText(holdingsSearch, 'ZZZ');
    await _pumpUntilGone(tester, holdingsAapl);
    await tester.enterText(holdingsSearch, '');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await _pumpUntil(tester, find.byType(SettingsPage));
    await _scrollTo(tester, 'Delete all data');
    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _waitForTradeCount(0);
    expect(await app.db.select(app.db.candles).get(), isEmpty);
    await _pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 8),
    );

    await _scrollTo(tester, 'Manage accounts', delta: -500);
    await tester.tap(
      find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.text('Manage accounts'),
          )
          .hitTestable(),
    );
    await _pumpUntil(tester, find.byType(AccountsPage));
    await tester.tap(find.byTooltip('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _pumpUntilGone(tester, find.text('E2E Local Renamed'));
    expect(accounts.activeAccount, 'Default');
    expect(accounts.accounts, ['Default']);

    final reloadedSettings = SettingsState();
    await reloadedSettings.initialized;
    expect(reloadedSettings.theme, ThemeMode.dark);
    expect(reloadedSettings.pureBlack, isTrue);
    expect(reloadedSettings.curveLines, isTrue);
    expect(reloadedSettings.visibleCurrencies, contains('NZD'));

    final reloadedAccounts = app.AccountManager();
    await reloadedAccounts.init();
    expect(reloadedAccounts.accounts, ['Default']);
    expect(reloadedAccounts.activeAccount, 'Default');

    expect(await app.db.select(app.db.trades).get(), isEmpty);
  });
}
