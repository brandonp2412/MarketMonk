import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Regression/feature test for issue #37: favorited stocks are surfaced as
  // an inline row on the Chart tab's portfolio view.
  testWidgets(
    'favorites row renders a seeded favorite, navigates to its chart, '
    'and persists un-favoriting',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
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
      final accounts = AccountManager();

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await db.candles.insertOne(
        CandlesCompanion.insert(
          symbol: 'AAPL',
          date: yesterday,
          close: const Value(180.0),
        ),
      );
      await db.candles.insertOne(
        CandlesCompanion.insert(
          symbol: 'AAPL',
          date: today,
          close: const Value(190.0),
        ),
      );

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpApp(tester, accounts);

      // Favorites row shows the seeded symbol with its latest price/change.
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.textContaining('190'), findsWidgets);
      expect(find.textContaining('5.56%'), findsOneWidget);

      // Tapping the card navigates into that stock's chart view.
      await tester.tap(find.text('AAPL'));
      await tester.pumpAndSettle();

      expect(find.text('Favorite'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // Un-favorite from the stock view.
      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();

      expect(find.text('Removed as favorite'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Re-mount the app (simulating a restart) to confirm the removal was
      // actually persisted, not just reflected in transient widget state.
      await _pumpApp(tester, AccountManager());
      expect(find.text('AAPL'), findsNothing);

      await db.close();
    },
  );

  testWidgets(
    'legacy single favoriteStock is migrated into favoriteStocks on load',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'favoriteStock': 'MSFT'});
      cacheSymbolMeta('MSFT', 'USD');
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = AccountManager();

      await db.candles.insertOne(
        CandlesCompanion.insert(
          symbol: 'MSFT',
          date: DateTime.now(),
          close: const Value(400.0),
        ),
      );

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpApp(tester, accounts);

      expect(find.text('MSFT'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('favoriteStocks'), ['MSFT']);
      expect(prefs.getString('favoriteStock'), null);

      await db.close();
    },
  );
}
