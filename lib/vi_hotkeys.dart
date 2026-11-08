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
    if (target == null) {
      if (action == ViAction.search) {
        final search = ViNavigation.instance.fallbackSearch;
        if (search != null) {
          search();
          return true;
        }
      }
      return false;
    }
    final VoidCallback? callback = switch (action) {
      ViAction.search => target.requestSearch,
      ViAction.next => () => target.moveFocus(1),
      ViAction.previous => () => target.moveFocus(-1),
      ViAction.select => target.toggleSelect,
      ViAction.delete => target.deleteFocus,
      ViAction.undo => target.undoDelete,
      ViAction.halfPageUp => target.halfPageUp,
      ViAction.halfPageDown => target.halfPageDown,
    };
    if (callback == null) return false;
    callback();
    return true;
  });
}
