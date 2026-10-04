import 'dart:async';

import 'sqlite_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('App renders tab navigation', (WidgetTester tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
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
    await seedTestSqlite({});
    final accounts = testAccountManager();

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
      await seedTestSqlite({});
      final accounts = testAccountManager();

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
      unawaited(
        Navigator.of(
          navContext,
        ).push(MaterialPageRoute(builder: (_) => const AccountsPage())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test Account');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(accounts.accounts, contains('Test Account'));
    },
  );

  testWidgets('desktop width uses persistent side navigation', (tester) async {
    await seedTestSqlite({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = testAccountManager();
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

    expect(find.byType(DesktopNav), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
    expect(find.text('Market Monk'), findsOneWidget);
    expect(tester.widget<DesktopNav>(find.byType(DesktopNav)).compact, isFalse);

    await tester.binding.setSurfaceSize(const Size(960, 900));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DesktopNav), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
    expect(tester.widget<DesktopNav>(find.byType(DesktopNav)).compact, isTrue);

    await tester.binding.setSurfaceSize(const Size(760, 900));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DesktopNav), findsNothing);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('desktop tab changes immediately without animation',
      (tester) async {
    await seedTestSqlite({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = testAccountManager();
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

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, 0);
    expect(find.byKey(const ValueKey('desktop-tab-transition')), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-HoldingsPage')));

    expect(pageView.controller!.page, 2);
    expect(pageView.controller!.position.isScrollingNotifier.value, isFalse);
    expect(find.byKey(const ValueKey('desktop-tab-transition')), findsNothing);
  });

  testWidgets(
      'desktop holdings uses a desktop toolbar instead of mobile chrome',
      (tester) async {
    await seedTestSqlite({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = testAccountManager();
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

    await tester.tap(find.byKey(const Key('desktop-HoldingsPage')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
