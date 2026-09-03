import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portfolio shows a friendly IBKR error instead of exception text',
      (tester) async {
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
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'secret-token',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(
          home: PortfolioPage(
            ibkrLoader: (_) async =>
                throw StateError('secret technical failure'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load Interactive Brokers'), findsOneWidget);
    expect(
      find.text(
        'MarketMonk couldn’t load your portfolio from your IBKR server. '
        'Check the server connection, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('IBKR settings'), findsOneWidget);
    expect(find.textContaining('secret technical failure'), findsNothing);
    expect(find.textContaining('Bad state:'), findsNothing);
  });
}
