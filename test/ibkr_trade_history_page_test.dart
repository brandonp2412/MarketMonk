import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IBKR history loads after opening an initially empty detail',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    final pending = Completer<IbkrTradeHistory>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'VOO',
              name: 'Vanguard S&P 500',
              position: null,
              trades: const [],
            ),
            ibkrTradeHistoryLoader: (_) => pending.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No trade history yet'), findsNothing);

    pending.complete(
      IbkrTradeHistory(
        available: true,
        trades: [
          IbkrTrade(
            symbol: 'VOO',
            name: 'Vanguard S&P 500',
            currency: 'USD',
            conid: 42,
            quantity: 10,
            price: 500,
            tradeType: 'open',
            tradeDate: DateTime(2026, 10, 12),
            realizedPnl: 0,
            commission: 1,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No trade history yet'), findsNothing);
    expect(find.text('BUY'), findsOneWidget);
    expect(find.textContaining('12 Oct 2026'), findsOneWidget);
  });

  testWidgets('cached empty IBKR history does not spin on navigation',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    final pending = Completer<IbkrTradeHistory>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'VOO',
              name: 'Vanguard',
              position: null,
              trades: const [],
            ),
            ibkrTradeHistoryLoader: (_) => pending.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No trade history yet'), findsOneWidget);
    pending.complete(const IbkrTradeHistory(available: true, trades: []));
    await tester.pumpAndSettle();
  });

  testWidgets('failed IBKR history can be retried', (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    var calls = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'VOO',
              name: 'Vanguard S&P 500',
              position: null,
              trades: const [],
            ),
            ibkrTradeHistoryLoader: (_) async {
              if (calls++ == 0) throw StateError('temporary gateway failure');
              return const IbkrTradeHistory(available: true, trades: []);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('IBKR trade history unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('No trade history yet'), findsOneWidget);
  });
  testWidgets('unavailable holdings history is retried on reactivation',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    await accounts.cachePortfolio(
      'Default',
      [
        Position(
          symbol: 'VOO',
          name: 'Vanguard S&P 500',
          nativeCurrency: 'USD',
          netShares: 10,
          avgCost: 500,
          currentPrice: 550,
          firstBuyDate: DateTime(2025),
          lastBuyDate: DateTime(2026),
        ),
      ],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
    );
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, isActive, child) => HoldingsPage(
              isActive: isActive,
              ibkrTradeHistoryLoader: (_) async {
                calls++;
                if (calls == 1) {
                  return const IbkrTradeHistory(available: false, trades: []);
                }
                return IbkrTradeHistory(
                  available: true,
                  trades: [
                    IbkrTrade(
                      symbol: 'VOO',
                      name: 'Vanguard',
                      currency: 'USD',
                      conid: 42,
                      quantity: 10,
                      price: 500,
                      tradeType: 'open',
                      tradeDate: DateTime(2026, 10, 12),
                      realizedPnl: 0,
                      commission: 1,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('VOO'), findsOneWidget);
    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.tap(find.text('VOO'));
    await tester.pumpAndSettle();
    expect(find.text('BUY'), findsOneWidget);
  });
  testWidgets('saved IBKR trades render immediately after app restart',
      (tester) async {
    await seedTestSqlite({});
    final firstSession = testAccountManager();
    await firstSession.init();
    await firstSession.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'test-token',
      ),
    );
    await firstSession.cachePortfolio(
      'Default',
      [
        Position(
          symbol: 'COHR',
          name: 'Coherent',
          nativeCurrency: 'USD',
          netShares: 2,
          avgCost: 100,
          currentPrice: 120,
          firstBuyDate: DateTime(2026, 1, 1),
          lastBuyDate: DateTime(2026, 1, 1),
        ),
      ],
      const IbkrAccountValue(value: 240, currency: 'USD'),
    );
    await firstSession.cacheIbkrTradeHistory(
      'Default',
      IbkrTradeHistory(
        available: true,
        trades: [
          IbkrTrade(
            symbol: 'COHR',
            name: 'Coherent',
            currency: 'USD',
            conid: 42,
            quantity: 2,
            price: 100,
            tradeType: 'open',
            tradeDate: DateTime(2026, 1, 1),
            realizedPnl: 0,
            commission: 0,
          ),
        ],
      ),
    );
    final restarted = testAccountManager();
    await restarted.init();
    expect(
      restarted.ibkrTradeHistoryCacheFor('Default')?.trades.single.symbol,
      'COHR',
    );
    var networkCalls = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: restarted),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            ibkrTradeHistoryLoader: (_) {
              networkCalls++;
              return Future.value(
                const IbkrTradeHistory(available: true, trades: []),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(networkCalls, 0);
    await tester.tap(find.text('COHR'));
    await tester.pumpAndSettle();
    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('No trade history yet'), findsNothing);
  });

  test('failed responses never replace previously cached broker history',
      () async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.cacheIbkrTradeHistory(
      'Default',
      IbkrTradeHistory(
        available: true,
        trades: [
          IbkrTrade(
            symbol: 'COHR',
            name: 'Coherent',
            currency: 'USD',
            conid: 42,
            quantity: 2,
            price: 100,
            tradeType: 'open',
            tradeDate: DateTime(2026, 1, 1),
            realizedPnl: 0,
            commission: 0,
          ),
        ],
      ),
    );
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: false, trades: []),
    );
    final restarted = testAccountManager();
    await restarted.init();
    expect(restarted.ibkrTradeHistoryCacheFor('Default')?.trades.length, 1);
  });
}
