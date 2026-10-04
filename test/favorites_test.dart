import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

Future<void> _pumpApp(WidgetTester tester, AccountManager accounts) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: const MyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'favorites row renders a seeded favorite, navigates to its chart, '
    'and persists un-favoriting',
    (WidgetTester tester) async {
      await seedTestSqlite({
        'favoriteStocks': ['AAPL'],
      });
      // Pre-seed the currency cache so syncCandles doesn't fire a real
      // network request for it (there's no network in the test sandbox).
      cacheSymbolMeta('AAPL', 'USD');
      final accounts = testAccountManager();

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await seedTestCandle('AAPL', yesterday, 180);
      await seedTestCandle('AAPL', today, 190);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpApp(tester, accounts);

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.textContaining('190'), findsWidgets);
      expect(find.textContaining('5.56%'), findsOneWidget);

      await tester.tap(find.text('AAPL'));
      await tester.pumpAndSettle();

      expect(find.text('Favorite'), findsOneWidget);

      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();

      expect(find.text('Removed as favorite'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Favorite'), findsNothing);

      // Re-mount the app (simulating a restart) to confirm the removal was
      // actually persisted, not just reflected in transient widget state.
      await _pumpApp(tester, testAccountManager());
      expect(find.text('AAPL'), findsNothing);
    },
  );

  testWidgets(
    'legacy single favoriteStock is migrated into favoriteStocks on load',
    (WidgetTester tester) async {
      await seedTestSqlite({'favoriteStock': 'MSFT'});
      cacheSymbolMeta('MSFT', 'USD');
      final accounts = testAccountManager();

      await seedTestCandle('MSFT', DateTime.now(), 400);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpApp(tester, accounts);

      expect(find.text('MSFT'), findsOneWidget);

      final prefs = await SqliteSettings.getInstance();
      expect(prefs.getStringList('favoriteStocks'), ['MSFT']);
      expect(prefs.getString('favoriteStock'), null);
    },
  );
}
