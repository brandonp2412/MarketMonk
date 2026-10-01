import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop holdings renders sortable data table', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    db = Database.connect(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() => db.close());

    final accounts = AccountManager();
    await accounts.init();
    final position = Position(
      symbol: 'VOO',
      name: 'VANGUARD S&P 500 ETF',
      nativeCurrency: 'USD',
      netShares: 10,
      avgCost: 500,
      currentPrice: 550,
      firstBuyDate: DateTime(2025),
      lastBuyDate: DateTime(2026),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: HoldingsPage(
            positionsLoader: (_) async => [position],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('VOO'), findsOneWidget);
    expect(find.text('VANGUARD S&P 500 ETF'), findsOneWidget);
    expect(find.text('Market value'), findsNWidgets(2));
    expect(find.text('Cost basis'), findsOneWidget);
    expect(find.text('Unrealized P/L'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Avg cost'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Return'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.text('Return'));
    await tester.pump();

    expect(tester.takeException(), null);
  });
}
