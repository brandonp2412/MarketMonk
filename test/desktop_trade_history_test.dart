import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/desktop_trade_history.dart';

void main() {
  testWidgets('desktop trade history filters and sorts transaction rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final trades = [
      Trade(
        id: 1,
        symbol: 'VOO',
        name: 'Vanguard S&P 500',
        quantity: 3,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026, 10, 1),
        realizedPL: 0,
        commission: 0.5,
        rawCurrency: 'USD',
      ),
      Trade(
        id: 2,
        symbol: 'VOO',
        name: 'Vanguard S&P 500',
        quantity: -1,
        price: 125,
        tradeType: 'close',
        tradeDate: DateTime(2026, 10, 20),
        realizedPL: 25,
        commission: 0.5,
        rawCurrency: 'USD',
      ),
    ];
    var addCalls = 0;
    Set<int>? deletedIds;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopTradeHistory(
            symbol: 'VOO',
            name: 'Vanguard S&P 500',
            position: null,
            trades: trades,
            totalRealizedUsd: 25,
            realizedToday: null,
            totalGain: 25,
            hasImportedRealized: true,
            brokerManaged: false,
            emptyState: const Text('Empty'),
            onAddTrade: () => addCalls++,
            onEditTrade: (_) async {},
            onDeleteTrade: (_) async {},
            onDeleteTrades: (ids) async => deletedIds = ids,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('desktop-trade-history-content')),
      findsOneWidget,
    );
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('SELL'), findsOneWidget);

    List<String?> visibleDates() {
      final table = tester.widget<DataTable>(find.byType(DataTable));
      return [
        for (final row in table.rows)
          (row.cells.first.child as DesktopContextMenu).child is Text
              ? ((row.cells.first.child as DesktopContextMenu).child as Text)
                  .data
              : null,
      ];
    }

    expect(visibleDates(), ['20 Oct 2026', '01 Oct 2026']);
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    expect(visibleDates(), ['01 Oct 2026', '20 Oct 2026']);

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('SELL'), findsNothing);
    expect(visibleDates(), ['01 Oct 2026']);

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    expect(find.text('BUY'), findsNothing);
    expect(find.text('SELL'), findsOneWidget);
    expect(visibleDates(), ['20 Oct 2026']);

    await tester.tap(find.text('Add trade'));
    expect(addCalls, 1);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    var table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.showCheckboxColumn, isTrue);
    table.rows.first.onSelectChanged!(true);
    await tester.pumpAndSettle();
    table = tester.widget<DataTable>(find.byType(DataTable));
    table.rows.last.onSelectChanged!(true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('desktop-trade-delete-selected')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('desktop-trade-delete-selected')));
    await tester.pumpAndSettle();
    expect(deletedIds, {1, 2});
  });
}
