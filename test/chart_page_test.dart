import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Regression test for issue #35: the chart page's first frame can be laid
  // out with degenerate constraints (e.g. before the Linux window reaches its
  // real size). The search-bar overlay height must be re-measured once the
  // window resizes, otherwise the time chips stay stuck under the search bar.
  testWidgets(
    'time chips stay below the search bar after a degenerate first frame',
    (WidgetTester tester) async {
      db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final accounts = AccountManager();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 30);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      // The temporarily tiny layout must not build the search overlay and
      // therefore must not report a RenderFlex overflow.
      expect(tester.takeException(), null);

      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      await tester.pump();

      final searchBottom = tester.getBottomLeft(find.byType(SearchBar)).dy;
      final chipTop = tester.getTopLeft(find.text('5d')).dy;
      expect(chipTop, greaterThanOrEqualTo(searchBottom));

      // Charts refresh through a pull gesture, and the scrollable leaves room
      // for the floating navigation dock rather than hiding its final rows.
      expect(find.byType(RefreshIndicator), findsOneWidget);
      final listView = tester.widget<ListView>(find.byType(ListView).first);
      final padding = listView.padding! as EdgeInsets;
      expect(padding.bottom, greaterThan(92));
      expect(find.text('Refresh'), findsNothing);
    },
  );

  testWidgets('cached IBKR portfolio period changes never refetch IBKR',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'ibkrAccountConfigs':
          '{"Default":{"enabled":true,"baseUrl":"https://ibkr.example.test","token":"secret-token"}}',
      'ibkrHistorySeeded:https://ibkr.example.test:Default:VOO': true,
    });
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accounts = AccountManager();
    await accounts.init();
    final cachedPosition = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );
    await accounts.cachePortfolio(
      'Default',
      [cachedPosition],
      const IbkrAccountValue(value: 5500, currency: 'USD'),
      netLiquidationUsd: 5500,
    );
    final now = DateTime.now();
    await db.into(db.candles).insert(
          CandlesCompanion.insert(
            symbol: 'VOO',
            date: DateTime(now.year, now.month, now.day),
            close: const Value(550),
          ),
        );

    var ibkrLoads = 0;
    Future<IbkrPortfolioSnapshot> loader(IbkrAccountConfig _) async {
      ibkrLoads++;
      throw StateError('IBKR should not be fetched for cached period changes');
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: Scaffold(body: ChartsPage(ibkrLoader: loader)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(ibkrLoads, 0);
    expect(find.textContaining('5,500'), findsWidgets);

    await tester.tap(find.text('5d'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10y'));
    await tester.pumpAndSettle();

    expect(ibkrLoads, 0);
  });

  testWidgets('exact ticker fallback is available while search is loading',
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

    final search = find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(EditableText),
    );
    await tester.enterText(search, 'GLD');
    await tester.pump();

    expect(find.text('Use "GLD" anyway'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(find.text('Use "GLD" anyway'), findsNothing);

    await db.close();
  });
}
