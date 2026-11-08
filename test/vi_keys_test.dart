import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/vi_keys.dart';

void main() {
  ViAction? action(
    LogicalKeyboardKey logicalKey, {
    bool shift = false,
    bool other = false,
    Map<ViAction, String> bindings = kDefaultViBindings,
  }) =>
      viActionFor(
        logicalKey: logicalKey,
        shiftPressed: shift,
        otherModifierPressed: other,
        bindings: bindings,
      );

  test('default bindings map to their vi actions', () {
    expect(action(LogicalKeyboardKey.keyJ), ViAction.next);
    expect(action(LogicalKeyboardKey.keyK), ViAction.previous);
    expect(action(LogicalKeyboardKey.keyD), ViAction.delete);
    expect(action(LogicalKeyboardKey.keyU), ViAction.undo);
    expect(
      action(LogicalKeyboardKey.space),
      ViAction.select,
    );
    expect(action(LogicalKeyboardKey.slash), ViAction.search);
  });

  test('shift selects the uppercase default bindings', () {
    expect(
      action(LogicalKeyboardKey.keyU, shift: true),
      ViAction.halfPageUp,
    );
    expect(
      action(LogicalKeyboardKey.keyD, shift: true),
      ViAction.halfPageDown,
    );
  });

  test('other modifiers disable vi actions', () {
    expect(action(LogicalKeyboardKey.keyJ, other: true), isNull);
  });

  test('rebindings are matched instead of the defaults', () {
    final bindings = {...kDefaultViBindings, ViAction.next: 'n'};
    expect(action(LogicalKeyboardKey.keyN, bindings: bindings), ViAction.next);
    expect(action(LogicalKeyboardKey.keyJ, bindings: bindings), isNull);
  });

  test('viKeyLabelFromEvent captures single printable keys', () {
    KeyDownEvent keyDown(
      LogicalKeyboardKey logicalKey,
      PhysicalKeyboardKey physicalKey, {
      String? character,
    }) =>
        KeyDownEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          character: character,
          timeStamp: Duration.zero,
        );

    expect(
      viKeyLabelFromEvent(
        keyDown(
          LogicalKeyboardKey.keyJ,
          PhysicalKeyboardKey.keyJ,
          character: 'J',
        ),
        shiftPressed: true,
        otherModifierPressed: false,
      ),
      'J',
    );
    expect(
      viKeyLabelFromEvent(
        keyDown(
          LogicalKeyboardKey.keyJ,
          PhysicalKeyboardKey.keyJ,
          character: 'j',
        ),
        shiftPressed: false,
        otherModifierPressed: false,
      ),
      'j',
    );
    expect(
      viKeyLabelFromEvent(
        keyDown(LogicalKeyboardKey.slash, PhysicalKeyboardKey.slash),
        shiftPressed: false,
        otherModifierPressed: false,
      ),
      '/',
    );
    expect(
      viKeyLabelFromEvent(
        keyDown(LogicalKeyboardKey.space, PhysicalKeyboardKey.space),
        shiftPressed: false,
        otherModifierPressed: false,
      ),
      ' ',
    );
  });

  test('viKeyLabelFromEvent rejects unusable keys', () {
    expect(
      viKeyLabelFromEvent(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        shiftPressed: false,
        otherModifierPressed: false,
      ),
      isNull,
    );
    expect(
      viKeyLabelFromEvent(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyJ,
          logicalKey: LogicalKeyboardKey.keyJ,
          character: 'j',
          timeStamp: Duration.zero,
        ),
        shiftPressed: false,
        otherModifierPressed: true,
      ),
      isNull,
    );
    expect(
      viKeyLabelFromEvent(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyJ,
          logicalKey: LogicalKeyboardKey.keyJ,
          timeStamp: Duration.zero,
        ),
        shiftPressed: false,
        otherModifierPressed: false,
      ),
      isNull,
    );
  });

  test('viKeyDisplayName names the space key', () {
    expect(viKeyDisplayName(' '), 'Space');
    expect(viKeyDisplayName('U'), 'U');
  });

  test('viBindingsWithSwap moves the old label to the displaced action', () {
    final swapped = viBindingsWithSwap(kDefaultViBindings, ViAction.next, 'k');
    expect(swapped[ViAction.next], 'k');
    expect(swapped[ViAction.previous], 'j');
    expect(swapped.length, kDefaultViBindings.length);
  });

  test('viBindingsWithSwap to a free label leaves the others untouched', () {
    final swapped = viBindingsWithSwap(kDefaultViBindings, ViAction.next, 'n');
    expect(
      swapped,
      {...kDefaultViBindings, ViAction.next: 'n'},
    );
  });

  test('viBindingsWithSwap does not mutate its input', () {
    final input = Map<ViAction, String>.of(kDefaultViBindings);
    viBindingsWithSwap(input, ViAction.next, 'k');
    expect(input, kDefaultViBindings);
  });
}
