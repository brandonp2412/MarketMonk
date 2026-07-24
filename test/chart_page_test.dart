import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() {
  // Regression test for issue #35: the chart page's first frame can be laid
  // out with degenerate constraints (e.g. before the Linux window reaches its
  // real size). The search-bar overlay height must be re-measured once the
  // window resizes, otherwise the time chips stay stuck under the search bar.
  testWidgets(
    'time chips stay below the search bar after a degenerate first frame',
    (WidgetTester tester) async {
      db = Database.connect(DatabaseConnection(NativeDatabase.memory()));
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

      // Swallow the RenderFlex overflows caused by the degenerate frame.
      while (tester.takeException() != null) {}

      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      await tester.pump();

      final searchBottom = tester.getBottomLeft(find.byType(SearchBar)).dy;
      final chipTop = tester.getTopLeft(find.text('5d')).dy;
      expect(chipTop, greaterThanOrEqualTo(searchBottom));
    },
  );
}
