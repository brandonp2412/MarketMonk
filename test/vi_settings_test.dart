import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ViNavigation.instance.target = null;
    ModalRouteTracker.instance.modalDepth = 0;
  });

  Finder bindingRow(ViAction action) =>
      find.byKey(Key('settings-vi-binding-${action.name}'));

  Finder doneButton() => find.byKey(const Key('vi-rebind-done'));

  Finder cancelButton() => find.byKey(const Key('vi-rebind-cancel'));

  Finder viModeRow() => find.byKey(const Key('settings-vi-mode'));

  Finder resetRow() => find.byKey(const Key('settings-vi-reset'));

  Finder dialogText(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  String rowKeyLabel(WidgetTester tester, ViAction action) => tester
      .widgetList<Text>(
        find.descendant(of: bindingRow(action), matching: find.byType(Text)),
      )
      .last
      .data!;

  Future<SettingsState> pumpSettings(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await seedTestSqlite({
      'systemColors': true,
      'showMarketClosed': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'Market Monk',
      packageName: 'com.example.market_monk',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final accounts = testAccountManager();
    await accounts.init();
    final settings = SettingsState();
    await settings.initialized;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> rebind(
    WidgetTester tester,
    ViAction action,
    LogicalKeyboardKey key,
  ) async {
    await tester.ensureVisible(bindingRow(action));
    await tester.tap(bindingRow(action));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(key);
    await tester.pump();
    await tester.sendKeyUpEvent(key);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNotNull);
    await tester.tap(doneButton());
    await tester.pumpAndSettle();
  }

  // Runs first: the test binding clears HardwareKeyboard handlers after every
  // test, and ViKeyState installs its modifier tracker only once per process.
  // The shift capture only works if this test's dialog performs the install.
  testWidgets('shift captures an uppercase key and cancel keeps the old key',
      (tester) async {
    final settings = await pumpSettings(tester, const Size(1200, 900));
    await tester.ensureVisible(bindingRow(ViAction.search));
    await tester.tap(bindingRow(ViAction.search));
    await tester.pumpAndSettle();
    expect(find.text('Bind Search'), findsOneWidget);
    expect(find.text('Press a key...'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(dialogText('U'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(cancelButton());
    await tester.pumpAndSettle();
    expect(find.text('Bind Search'), findsNothing);
    expect(settings.viBindings[ViAction.search], '/');
  });

  testWidgets(
      'desktop keyboard card lists every vi action with its default key',
      (tester) async {
    final settings = await pumpSettings(tester, const Size(1400, 900));
    expect(find.text('Keyboard'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: viModeRow(), matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );
    const defaults = {
      ViAction.search: '/',
      ViAction.next: 'j',
      ViAction.previous: 'k',
      ViAction.select: 'Space',
      ViAction.delete: 'd',
      ViAction.undo: 'u',
      ViAction.halfPageUp: 'U',
      ViAction.halfPageDown: 'D',
    };
    for (final action in ViAction.values) {
      expect(bindingRow(action), findsOneWidget, reason: action.name);
      expect(rowKeyLabel(tester, action), defaults[action]);
    }
    expect(resetRow(), findsOneWidget);
    expect(settings.viBindings, kDefaultViBindings);
  });

  testWidgets('rebind dialog captures a key and persists it', (tester) async {
    final settings = await pumpSettings(tester, const Size(1200, 900));
    await tester.ensureVisible(bindingRow(ViAction.search));
    await tester.tap(bindingRow(ViAction.search));
    await tester.pumpAndSettle();
    expect(find.text('Bind Search'), findsOneWidget);
    expect(find.text('Press a key...'), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(dialogText('a'), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNotNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.tap(doneButton());
    await tester.pumpAndSettle();
    expect(find.text('Bind Search'), findsNothing);
    expect(settings.viBindings[ViAction.search], 'a');
    expect(rowKeyLabel(tester, ViAction.search), 'a');
    expect(
      (await SqliteSettings.getInstance()).getString('viBindings'),
      contains('"search":"a"'),
    );
  });

  testWidgets('binding a key that is already used swaps the two bindings',
      (tester) async {
    final settings = await pumpSettings(tester, const Size(1200, 900));
    await rebind(tester, ViAction.search, LogicalKeyboardKey.keyA);
    await rebind(tester, ViAction.next, LogicalKeyboardKey.keyA);
    expect(settings.viBindings[ViAction.next], 'a');
    expect(settings.viBindings[ViAction.search], 'j');
  });

  testWidgets('reset to defaults restores and persists every binding',
      (tester) async {
    final settings = await pumpSettings(tester, const Size(1200, 900));
    await rebind(tester, ViAction.search, LogicalKeyboardKey.keyA);
    await tester.ensureVisible(resetRow());
    await tester.tap(resetRow());
    await tester.pumpAndSettle();
    expect(settings.viBindings, kDefaultViBindings);
    expect(rowKeyLabel(tester, ViAction.search), '/');
    expect(
      (await SqliteSettings.getInstance()).getString('viBindings'),
      jsonEncode(
        kDefaultViBindings.map(
          (action, label) => MapEntry(action.name, label),
        ),
      ),
    );
  });

  testWidgets('toggling vi mode persists', (tester) async {
    final settings = await pumpSettings(tester, const Size(1200, 900));
    await tester.ensureVisible(viModeRow());
    await tester.tap(viModeRow());
    await tester.pumpAndSettle();
    expect(settings.viModeEnabled, isFalse);
    expect(
      (await SqliteSettings.getInstance()).getBool('viModeEnabled'),
      isFalse,
    );
  });

  testWidgets('search filters the keyboard section in and out', (tester) async {
    await pumpSettings(tester, const Size(1200, 900));
    await tester.enterText(find.byKey(const Key('settings-search')), 'vi');
    await tester.pumpAndSettle();
    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.text('Vi key bindings'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('settings-search')), 'amoled');
    await tester.pumpAndSettle();
    expect(find.text('Keyboard'), findsNothing);

    await tester.enterText(find.byKey(const Key('settings-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Keyboard'), findsOneWidget);
  });

  testWidgets('mobile keyboard section lists the vi controls', (tester) async {
    final settings = await pumpSettings(tester, const Size(430, 940));
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    // The mobile list builds children lazily. scrollUntilVisible aligns the
    // target without pumping, so pump a frame to keep the element tree in
    // sync with the scroll position before the next lookup.
    final targets = <Finder>[
      find.text('Keyboard'),
      viModeRow(),
      for (final action in ViAction.values) bindingRow(action),
      resetRow(),
    ];
    for (final target in targets) {
      await tester.scrollUntilVisible(target, 300, scrollable: list);
      await tester.pump();
      expect(target, findsOneWidget);
    }
    // Scroll back to the top of the section to read the row label and switch.
    await tester.scrollUntilVisible(viModeRow(), -300, scrollable: list);
    await tester.pump();
    expect(rowKeyLabel(tester, ViAction.search), '/');
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: viModeRow(), matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );
    expect(settings.viModeEnabled, isTrue);
  });
}
