import 'package:flutter/services.dart';

const viReservedKeys = {'f', 'F', '?', ',', '1', '2', '3'};

enum ViAction {
  search,
  next,
  previous,
  select,
  delete,
  undo,
  halfPageUp,
  halfPageDown,
}

extension ViActionLabel on ViAction {
  String get label => switch (this) {
        ViAction.search => 'Search',
        ViAction.next => 'Next holding',
        ViAction.previous => 'Previous holding',
        ViAction.select => 'Select focused holding',
        ViAction.delete => 'Delete focused holding',
        ViAction.undo => 'Undo last delete',
        ViAction.halfPageUp => 'Half page up',
        ViAction.halfPageDown => 'Half page down',
      };
}

const Map<ViAction, String> kDefaultViBindings = {
  ViAction.search: '/',
  ViAction.next: 'j',
  ViAction.previous: 'k',
  ViAction.select: ' ',
  ViAction.delete: 'd',
  ViAction.undo: 'u',
  ViAction.halfPageUp: 'U',
  ViAction.halfPageDown: 'D',
};

final Set<PhysicalKeyboardKey> _viModifierKeys = {
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
};

/// Tracks which modifier keys are physically held down, independent of focus.
class ViKeyState {
  ViKeyState._();

  static final ViKeyState instance = ViKeyState._();

  final Set<PhysicalKeyboardKey> _pressed = {};
  bool _installed = false;

  void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_viModifierKeys.contains(event.physicalKey)) return false;
    if (event is KeyDownEvent) {
      _pressed.add(event.physicalKey);
    } else if (event is KeyUpEvent) {
      _pressed.remove(event.physicalKey);
    }
    return false;
  }

  bool get shiftPressed =>
      _pressed.contains(PhysicalKeyboardKey.shiftLeft) ||
      _pressed.contains(PhysicalKeyboardKey.shiftRight);

  bool get controlPressed =>
      _pressed.contains(PhysicalKeyboardKey.controlLeft) ||
      _pressed.contains(PhysicalKeyboardKey.controlRight);

  bool get altPressed =>
      _pressed.contains(PhysicalKeyboardKey.altLeft) ||
      _pressed.contains(PhysicalKeyboardKey.altRight);

  bool get metaPressed =>
      _pressed.contains(PhysicalKeyboardKey.metaLeft) ||
      _pressed.contains(PhysicalKeyboardKey.metaRight);

  bool get anyModifier =>
      shiftPressed || controlPressed || altPressed || metaPressed;
}

/// Matches [logicalKey] against [bindings]; an uppercase bound label needs
/// shift held, a lowercase or symbol label must not have it.
ViAction? viActionFor({
  required LogicalKeyboardKey logicalKey,
  required bool shiftPressed,
  required bool otherModifierPressed,
  required Map<ViAction, String> bindings,
}) {
  if (otherModifierPressed) return null;
  final label = logicalKey.keyLabel;
  for (final entry in bindings.entries) {
    final bound = entry.value;
    if (bound.length != 1) continue;
    if (label.toLowerCase() == bound.toLowerCase() &&
        (bound != bound.toLowerCase()) == shiftPressed) {
      return entry.key;
    }
  }
  return null;
}

/// Captures a bindable label from a key press, or null if the key is not
/// usable as a vi binding.
String? viKeyLabelFromEvent(
  KeyEvent event, {
  required bool shiftPressed,
  required bool otherModifierPressed,
}) {
  if (event is! KeyDownEvent || otherModifierPressed) return null;
  final label = event.logicalKey.keyLabel;
  if (label.length != 1) return null;
  final codeUnit = label.codeUnitAt(0);
  if (codeUnit < 0x20 || codeUnit > 0x7E) return null;
  if (_isAsciiLetter(codeUnit)) {
    return shiftPressed ? label.toUpperCase() : label.toLowerCase();
  }
  return label;
}

bool _isAsciiLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

String viKeyDisplayName(String label) => label == ' ' ? 'Space' : label;

/// Returns a new binding map where [action] takes [label]; the action that
/// already used [label] takes [action]'s old label instead.
Map<ViAction, String> viBindingsWithSwap(
  Map<ViAction, String> current,
  ViAction action,
  String label,
) {
  final swapped = Map<ViAction, String>.of(current);
  final oldLabel = swapped[action];
  ViAction? displaced;
  for (final entry in swapped.entries) {
    if (entry.key != action && entry.value == label) {
      displaced = entry.key;
      break;
    }
  }
  if (displaced != null && oldLabel != null) {
    swapped[displaced] = oldLabel;
  }
  swapped[action] = label;
  return swapped;
}
