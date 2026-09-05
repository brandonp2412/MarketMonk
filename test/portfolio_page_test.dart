import 'dart:async';

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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Position cachedPosition() => Position(
        symbol: 'VOO',
        name: 'VANGUARD S&P 500 ETF',
        nativeCurrency: 'USD',
        netShares: 10,
        avgCost: 500,
        currentPrice: 550,
        firstBuyDate: DateTime(2025),
        lastBuyDate: DateTime(2026),
      );

  Future<AccountManager> configuredAccounts() async {
    final accounts = AccountManager();
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

  Widget app(AccountManager accounts, PortfolioPage page) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(home: page),
      );

  testWidgets('portfolio shows a spinner while uncached data is loading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());
    final accounts = await configuredAccounts();
    final pending = Completer<IbkrPortfolioSnapshot>();

    await tester.pumpWidget(
      app(accounts, PortfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('portfolio renders persistent cache without waiting for refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());
    final accounts = await configuredAccounts();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    final pending = Completer<IbkrPortfolioSnapshot>();

    await tester.pumpWidget(
      app(accounts, PortfolioPage(ibkrLoader: (_) => pending.future)),
    );
    await tester.pump();

    expect(find.text('VOO'), findsOneWidget);
    expect(find.text('VANGUARD S&P 500 ETF'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('portfolio cache survives AccountManager reinitialization', () async {
    SharedPreferences.setMockInitialValues({});
    final accounts = AccountManager();
    await accounts.init();
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition()],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
    );

    final reloaded = AccountManager();
    await reloaded.init();
    final cached = reloaded.portfolioCacheFor('Default');

    expect(cached == null, isFalse);
    expect(cached!.positions.single.symbol, 'VOO');
    expect(cached.positions.single.currentPrice, 550);
    expect(cached.netLiquidation?.value, 5500);
    expect(cached.netLiquidationUsd, 5500);
  });

  testWidgets('portfolio shows a friendly IBKR error instead of exception text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = await configuredAccounts();

    await tester.pumpWidget(
      app(
        accounts,
        PortfolioPage(
          ibkrLoader: (_) async => throw StateError('secret technical failure'),
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
  });
}
