import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';

void installDesktopViHotkeys(SettingsState settings) {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  ViKeyState.instance.ensureInstalled();

  HardwareKeyboard.instance.addHandler((event) {
    if (event is! KeyDownEvent) return false;
    if (!settings.viModeEnabled) return false;
    if (ModalRouteTracker.instance.modalDepth > 0) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editableFocused = focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editableFocused) return false;

    final action = viActionFor(
      logicalKey: event.logicalKey,
      shiftPressed: ViKeyState.instance.shiftPressed,
      otherModifierPressed: ViKeyState.instance.controlPressed ||
          ViKeyState.instance.altPressed ||
          ViKeyState.instance.metaPressed,
      bindings: settings.viBindings,
    );
    if (action == null) return false;

    final target = ViNavigation.instance.target;
    if (target != null) {
      switch (action) {
        case ViAction.search:
          target.requestSearch();
        case ViAction.next:
          target.moveFocus(1);
        case ViAction.previous:
          target.moveFocus(-1);
        case ViAction.select:
          target.toggleSelect?.call();
        case ViAction.delete:
          target.deleteFocus?.call();
        case ViAction.undo:
          target.undoDelete?.call();
        case ViAction.halfPageUp:
          target.halfPageUp?.call();
        case ViAction.halfPageDown:
          target.halfPageDown?.call();
      }
    }
    return false;
  });
}
