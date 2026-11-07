import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/debug_hotkeys.dart';

void main() {
  KeyDownEvent keyDown(String? character) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyR,
    logicalKey: LogicalKeyboardKey.keyR,
    character: character,
    timeStamp: Duration.zero,
  );

  DebugHotkeyAction? actionFor(
    KeyEvent event, {
    bool editableFocused = false,
    bool shiftPressed = false,
    bool controlPressed = false,
    bool altPressed = false,
    bool metaPressed = false,
  }) => debugHotkeyAction(
    event,
    editableFocused: editableFocused,
    shiftPressed: shiftPressed,
    controlPressed: controlPressed,
    altPressed: altPressed,
    metaPressed: metaPressed,
  );

  test('r reloads and R restarts', () {
    expect(actionFor(keyDown('r')), DebugHotkeyAction.reload);
    expect(
      actionFor(keyDown('R'), shiftPressed: true),
      DebugHotkeyAction.restart,
    );
    expect(
      actionFor(keyDown(null), shiftPressed: true),
      DebugHotkeyAction.restart,
    );
  });

  test('does not intercept text input, modifiers, or repeated keys', () {
    expect(actionFor(keyDown('r'), editableFocused: true), isNull);
    expect(actionFor(keyDown('r'), controlPressed: true), isNull);
    expect(actionFor(keyDown('r'), altPressed: true), isNull);
    expect(actionFor(keyDown('r'), metaPressed: true), isNull);
    expect(
      actionFor(
        KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.keyR,
          logicalKey: LogicalKeyboardKey.keyR,
          character: 'r',
          timeStamp: Duration.zero,
        ),
      ),
      isNull,
    );
    expect(
      actionFor(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyT,
          logicalKey: LogicalKeyboardKey.keyT,
          character: 't',
          timeStamp: Duration.zero,
        ),
      ),
      isNull,
    );
  });

  test('finds parent PID even when the executable name has spaces', () {
    expect(linuxParentPid('123 (Market Monk (debug)) S 5678 1 2 3'), 5678);
    expect(linuxParentPid('invalid'), isNull);
  });

  test('sends signals only to flutter run or flutter attach', () {
    final separator = String.fromCharCode(0);
    expect(
      isFlutterToolRunner(
        [
          '/usr/bin/dart',
          '/sdk/flutter_tools.snapshot',
          'run',
          '-d',
          'linux',
        ].join(separator),
      ),
      isTrue,
    );
    expect(
      isFlutterToolRunner(
        [
          '/usr/bin/dart',
          '/sdk/flutter_tools.snapshot',
          'attach',
        ].join(separator),
      ),
      isTrue,
    );
    expect(
      isFlutterToolRunner(
        [
          '/usr/bin/dart',
          '/sdk/flutter_tools.snapshot',
          'daemon',
        ].join(separator),
      ),
      isFalse,
    );
    expect(
      isFlutterToolRunner(['/usr/bin/unrelated', 'run'].join(separator)),
      isFalse,
    );
  });
  test('hotkey feedback identifies the requested action', () {
    expect(debugHotkeyToastLabel(DebugHotkeyAction.reload), 'Hot reloading…');
    expect(debugHotkeyToastLabel(DebugHotkeyAction.restart), 'Hot restarting…');
  });
}
