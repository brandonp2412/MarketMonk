import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders tab navigation', (WidgetTester tester) async {
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final accounts = AccountManager();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Charts'), findsOneWidget);
    expect(find.bySemanticsLabel('Portfolio'), findsOneWidget);
    expect(find.bySemanticsLabel('Holdings'), findsOneWidget);
  });

  testWidgets('default account cannot be renamed', (WidgetTester tester) async {
    final accounts = AccountManager();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: accounts,
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default'), findsOneWidget);
    expect(find.byTooltip('Rename account'), findsNothing);
    expect(find.byTooltip('Delete account'), findsNothing);
  });

  testWidgets(
    'adding account does not cause overlay assertion while MyApp rebuilds',
    (WidgetTester tester) async {
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = AccountManager();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsState()),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pump();

      // Push AccountsPage directly onto MyApp's navigator to reproduce the
      // real scenario: AccountsPage is a child route inside the same Overlay
      // that MyApp's MaterialApp owns.
      final navContext = tester.element(find.byType(MyHomePage));
      Navigator.of(
        navContext,
      ).push(MaterialPageRoute(builder: (_) => const AccountsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test Account');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(accounts.accounts, contains('Test Account'));
    },
  );
}
