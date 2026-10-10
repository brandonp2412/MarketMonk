import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_line_chart.dart';
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
    'favorites toggle graph lines and selection without opening search',
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
      await seedTestCandle(
        'AAPL',
        DateTime(today.year - 1, today.month, today.day - 1),
        170,
      );
      await seedTestCandle(
        'AAPL',
        DateTime(today.year, today.month - 1, today.day),
        170,
      );
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
      expect(find.text('+11.76%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chart-period-5d')));
      await tester.pumpAndSettle();
      expect(find.text('+5.56%'), findsOneWidget);
      expect(find.text('+11.76%'), findsNothing);

      await tester.tap(find.byKey(const Key('chart-period-1y')));
      await tester.pumpAndSettle();
      expect(find.text('+11.76%'), findsOneWidget);

      await tester.tap(find.text('AAPL'));
      await tester.pumpAndSettle();

      expect(find.text('Favorite'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      final chart =
          tester.widget<MarketLineChart>(find.byType(MarketLineChart));
      expect(chart.series.single.name, 'AAPL');
      expect(chart.series.single.points.first.y, 0);
      expect(chart.series.single.points.last.y, greaterThan(0));
      final search = tester.widget<SearchBar>(find.byType(SearchBar));
      expect(search.controller!.text, isEmpty);

      await tester.tap(find.text('AAPL'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.byType(MarketLineChart), findsNothing);
      expect(find.text('AAPL'), findsOneWidget);
      final prefs = await SqliteSettings.getInstance();
      expect(prefs.getStringList('favoriteStocks'), ['AAPL']);
    },
  );

  testWidgets(
    'legacy single favoriteStock is migrated into favoriteStocks on load',
    (WidgetTester tester) async {
      await seedTestSqlite({'favoriteStock': 'MSFT'});
      cacheSymbolMeta('MSFT', 'USD');
      final accounts = testAccountManager();

      final today = DateTime.now();
      await seedTestCandle(
        'MSFT',
        DateTime(today.year - 1, today.month, today.day - 1),
        390,
      );
      await seedTestCandle('MSFT', today, 400);

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
