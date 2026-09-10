import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';

void main() {
  setUp(() {
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
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
    expect(await db.select(db.trades).get(), isEmpty);
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
    expect(await db.select(db.trades).get(), isEmpty);
    expect(tester.takeException(), null);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
