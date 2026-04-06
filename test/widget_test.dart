import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsState(),
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('Holdings'), findsOneWidget);
  });
}
