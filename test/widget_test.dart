import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders tab navigation', (WidgetTester tester) async {
    db = Database.connect(DatabaseConnection(NativeDatabase.memory()));
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
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('Holdings'), findsOneWidget);
  });
}
