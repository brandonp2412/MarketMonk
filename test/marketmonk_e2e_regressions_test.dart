import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Holdings never shows another account after switching',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    await ensureTestProfile('Other');
    await seedTestTrade(
      accountName: 'Other',
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 2,
      price: 300,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 20),
    );
    allRatesFromUsd['USD'] = 1;
    final accounts = testAccountManager();
    await accounts.init();
    final settings = SettingsState();
    await settings.initialized;
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: accounts),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            positionsLoader: (trades) async => computePositions(
              trades,
              {'AAPL': 340},
              nativeCurrencies: {'AAPL': 'USD'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsNothing);

    await accounts.switchAccount('Other');
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);

    await accounts.switchAccount('Default');
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsNothing);
    expect(find.text('No stocks yet'), findsOneWidget);
  });

  testWidgets('Holdings recalculates after CSV import while inactive',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    allRatesFromUsd['USD'] = 1;
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.cachePortfolio('Default', [], null);
    final settings = SettingsState();
    await settings.initialized;
    addTearDown(settings.dispose);

    Widget screen(bool active) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: accounts),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            home: HoldingsPage(
              isActive: active,
              positionsLoader: (trades) async => computePositions(
                trades,
                {'AAPL': 340},
                nativeCurrencies: {'AAPL': 'USD'},
              ),
            ),
          ),
        );

    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    await seedTestTrade(
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 4,
      price: 200,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 1),
    );
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('1 open · 1 total symbols'), findsOneWidget);
  });

  testWidgets('Trade details update immediately after editing and selling',
      (tester) async {
    await seedTestSqlite({});
    allRatesFromUsd['USD'] = 1;
    await seedTestTrade(
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 2,
      price: 300,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 20),
    );
    final accounts = testAccountManager();
    await accounts.init();
    final settings = SettingsState();
    await settings.initialized;
    addTearDown(settings.dispose);
    final originalTrade =
        (await profileDataRepository.readTradesForAccount('Default')).single;
    final profileId = await profileDataRepository.profileIdForName('Default');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: accounts),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          home: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'AAPL',
              name: 'Apple',
              position: Position(
                symbol: 'AAPL',
                name: 'Apple',
                nativeCurrency: 'USD',
                netShares: 2,
                avgCost: 300,
                currentPrice: 343.91,
                firstBuyDate: DateTime(2026, 10, 20),
                lastBuyDate: DateTime(2026, 10, 20),
              ),
              trades: [originalTrade],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.0000'), findsOneWidget);
    expect(find.text(r'$300.00'), findsOneWidget);

    await profileDataRepository.updateTrade(
      profileId: profileId,
      tradeId: originalTrade.id,
      quantity: 3,
      price: 310,
    );
    await tester.pumpAndSettle();
    expect(find.text('3.0000'), findsOneWidget);
    expect(find.text(r'$310.00'), findsOneWidget);
    expect(find.text(r'$1,031.73'), findsOneWidget);

    await seedTestTrade(
      symbol: 'AAPL',
      name: 'Apple',
      quantity: -1,
      price: 350,
      tradeType: 'close',
      tradeDate: DateTime(2026, 10, 21),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.0000'), findsOneWidget);
    expect(find.text(r'$687.82'), findsOneWidget);
  });
}
