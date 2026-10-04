import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'sqlite_test_support.dart';

void main() {
  setUp(() async {
    await seedTestSqlite({
      'accounts': ['Default'],
      'activeAccount': 'Default',
    });
  });

  testWidgets('invalid trade amount is rejected without throwing',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: EditTickerPage(symbol: 'VTI')));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Amount'),
      'not-a-number',
    );
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Save'));
    await tester.pump();

    expect(
      find.text('Enter a valid amount greater than zero.'),
      findsOneWidget,
    );
    expect(await testDatabase.select(testDatabase.trades).get(), isEmpty);
    expect(tester.takeException(), null);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('invalid trade price is rejected without throwing',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: EditTickerPage(symbol: 'VTI')));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Price'),
      '',
    );
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Save'));
    await tester.pump();

    expect(
      find.text('Enter a valid price greater than zero.'),
      findsOneWidget,
    );
    expect(await testDatabase.select(testDatabase.trades).get(), isEmpty);
    expect(tester.takeException(), null);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
