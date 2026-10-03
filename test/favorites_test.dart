import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

Future<void> _disposeTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpApp(WidgetTester tester, AccountManager accounts) async {
  await accounts.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsState(
            localCurrencyDetector: () async => 'USD',
          ),
        ),
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
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = testAccountManager();

      final today = DateTime.now();
      final oldest = today.subtract(defaultMarketCandleLookback);
      await seedTestCandle(symbol: 'AAPL', date: oldest, close: 180);
      await seedTestCandle(symbol: 'AAPL', date: today, close: 190);

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

      await _disposeTestApp(tester);
      await db.close();
    },
  );

  testWidgets(
    'legacy single favoriteStock is migrated into favoriteStocks on load',
    (WidgetTester tester) async {
      await seedTestSqlite({'favoriteStock': 'MSFT'});
      cacheSymbolMeta('MSFT', 'USD');
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = testAccountManager();

      final today = DateTime.now();
      await seedTestCandle(
        symbol: 'MSFT',
        date: today.subtract(defaultMarketCandleLookback),
        close: 390,
      );
      await seedTestCandle(symbol: 'MSFT', date: today, close: 400);

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

      await _disposeTestApp(tester);
      await db.close();
    },
  );
}
