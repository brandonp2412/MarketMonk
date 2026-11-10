import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/theme_color_wheel.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:market_monk/vi_hotkeys.dart';
import 'package:market_monk/vi_overlay.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  test('hint labels stay unique and never prefix another label', () {
    for (final count in [0, 1, 11, 12, 121, 122, 1500]) {
      final labels = viHintLabels(count);
      expect(labels.toSet().length, count);
      expect(
        labels.map((label) => label.length).toSet().length,
        lessThanOrEqualTo(1),
      );
      expect(
        labels.every((label) => label.split('').every(viHintAlphabet.contains)),
        isTrue,
      );
    }
  });

  test('wheel maps radius to saturation and angle to hue', () {
    final center = themeWheelColor(const Offset(100, 100), 200, 1);
    final edge = themeWheelColor(const Offset(200, 100), 200, 1);
    expect(center, Colors.white);
    expect(edge, const Color(0xffff0000));
    expect(themeWheelColor(const Offset(300, 100), 200, 1), edge);
  });

  testWidgets('hint letters never also trigger a delete binding',
      (tester) async {
    await seedTestSqlite({});
    final settings = SettingsState();
    await settings.initialized;
    installDesktopViHotkeys(settings);
    var deletes = 0;
    var tapped = -1;
    ViNavigation.instance.target = ViTarget(
      requestSearch: () {},
      moveFocus: (_) {},
      deleteFocus: () => deletes++,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          builder: (context, child) => ViOverlay(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < 7; i++)
                  TextButton(
                    onPressed: () => tapped = i,
                    child: Text('Action $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD, character: 'd');
    await tester.pump();
    expect(tapped, 6);
    expect(deletes, 0);
    await tester.pumpWidget(const SizedBox());
    ViNavigation.instance.target = null;
    settings.dispose();
  });

  testWidgets(
      'hints activate buttons, help lists bindings, text entry is left alone',
      (tester) async {
    await seedTestSqlite({});
    final settings = SettingsState();
    await settings.initialized;
    var taps = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          builder: (context, child) => ViOverlay(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => taps++,
                  child: const Text('Action'),
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.pump();
    expect(find.text('q'), findsOneWidget);
    expect(ViNavigation.instance.overlayActive, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ, character: 'q');
    await tester.pump();
    expect(taps, 1);
    expect(ViNavigation.instance.overlayActive, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Keyboard controls'), findsOneWidget);
    expect(find.text('Next holding'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.pump();
    expect(ViNavigation.instance.overlayActive, isFalse);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
