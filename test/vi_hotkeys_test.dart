import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/vi_hotkeys.dart';
import 'package:market_monk/vi_navigation.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ViNavigation.instance.target = null;
    ViNavigation.instance.fallbackSearch = null;
    ViNavigation.instance.fallbackMoveFocus = null;
    ModalRouteTracker.instance.modalDepth = 0;
  });

  testWidgets('desktop vi keys dispatch and search falls back across tabs',
      (tester) async {
    await seedTestSqlite({});
    final settings = SettingsState();
    await settings.initialized;
    installDesktopViHotkeys(settings);

    var movement = 0;
    var searchCount = 0;
    ViNavigation.instance.target = ViTarget(
      requestSearch: () => searchCount++,
      moveFocus: (delta) => movement += delta,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Focus(autofocus: true, child: SizedBox())),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    expect(movement, 0);
    expect(searchCount, 1);

    ViNavigation.instance.target = null;
    ViNavigation.instance.fallbackSearch = () => searchCount++;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    expect(searchCount, 2);

    var fallbackMovement = 0;
    ViNavigation.instance.fallbackMoveFocus =
        (delta) => fallbackMovement += delta;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    expect(fallbackMovement, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    expect(fallbackMovement, 0);
  });
}
