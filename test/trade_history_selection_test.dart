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

  testWidgets('mobile trade tap actions and long-press batch deletion',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seedTestSqlite({});
    allRatesFromUsd['USD'] = 1;
    await seedTestTrade(
      symbol: 'VOO',
      name: 'Vanguard',
      quantity: 2,
      price: 100,
      tradeType: 'open',
      tradeDate: DateTime(2026, 10, 1),
    );
    await seedTestTrade(
      symbol: 'VOO',
      name: 'Vanguard',
      quantity: -1,
      price: 120,
      tradeType: 'close',
      tradeDate: DateTime(2026, 10, 20),
    );
    final trades = await profileDataRepository.readTradesForAccount('Default');
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
          home: TradeHistoryPage(
            summary: SymbolSummary(
              symbol: 'VOO',
              name: 'Vanguard',
              position: Position(
                symbol: 'VOO',
                name: 'Vanguard',
                nativeCurrency: 'USD',
                netShares: 1,
                avgCost: 100,
                currentPrice: 120,
                firstBuyDate: DateTime(2026, 10, 1),
                lastBuyDate: DateTime(2026, 10, 1),
              ),
              trades: trades,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstTile = find.byKey(ValueKey('trade-tile-${trades.last.id}'));
    final secondTile = find.byKey(ValueKey('trade-tile-${trades.first.id}'));
    expect(trades, hasLength(2));
    expect(
      firstTile,
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .take(40)
          .join(' | '),
    );
    ListTile tile(Finder finder) => tester.widget<ListTile>(
          find.descendant(of: finder, matching: find.byType(ListTile)),
        );
    expect((tile(firstTile).leading as SizedBox).width, 40);
    expect((tile(firstTile).leading as SizedBox).height, 40);

    await tester.tap(firstTile);
    await tester.pumpAndSettle();
    expect(find.text('Edit trade'), findsOneWidget);
    expect(find.text('Delete trade'), findsOneWidget);
    expect(find.text('Copy trade'), findsOneWidget);
    await tester.tapAt(const Offset(12, 120));
    await tester.pumpAndSettle();

    await tester.longPress(firstTile);
    await tester.pumpAndSettle();
    expect(tile(firstTile).selected, isTrue);
    expect((tile(firstTile).leading as SizedBox).width, 40);
    expect((tile(firstTile).leading as SizedBox).height, 40);
    await tester.scrollUntilVisible(
      secondTile,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(secondTile);
    await tester.pumpAndSettle();
    await tester.tap(secondTile);
    await tester.pumpAndSettle();
    expect(tile(secondTile).selected, isTrue);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('trade-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 trades?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      await profileDataRepository.readTradesForAccount('Default'),
      isEmpty,
    );
  });
}
