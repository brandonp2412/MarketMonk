import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

enum DebugHotkeyAction { reload, restart }

final debugHotkeyMessengerKey = GlobalKey<ScaffoldMessengerState>();

String debugHotkeyToastLabel(DebugHotkeyAction action) => switch (action) {
      DebugHotkeyAction.reload => 'Hot reloading…',
      DebugHotkeyAction.restart => 'Hot restarting…',
    };

void _showDebugHotkeyToast(DebugHotkeyAction action) {
  final messenger = debugHotkeyMessengerKey.currentState;
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(debugHotkeyToastLabel(action)),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      width: 240,
    ),
  );
}

DebugHotkeyAction? debugHotkeyAction(
  KeyEvent event, {
  required bool editableFocused,
  required bool shiftPressed,
  required bool controlPressed,
  required bool altPressed,
  required bool metaPressed,
}) {
  if (event is! KeyDownEvent ||
      event.logicalKey != LogicalKeyboardKey.keyR ||
      editableFocused ||
      controlPressed ||
      altPressed ||
      metaPressed) {
    return null;
  }

  final uppercase =
      event.character == 'R' || (event.character == null && shiftPressed);
  return uppercase ? DebugHotkeyAction.restart : DebugHotkeyAction.reload;
}

int? linuxParentPid(String stat) {
  final commandEnd = stat.lastIndexOf(') ');
  if (commandEnd < 0) return null;
  final fields = stat.substring(commandEnd + 2).trim().split(RegExp(r'\s+'));
  if (fields.length < 2) return null;
  return int.tryParse(fields[1]);
}

bool isFlutterToolRunner(String commandLine) {
  final args = commandLine.split('\x00');
  final toolIndex = args.indexWhere(
    (arg) =>
        arg == 'flutter_tools.snapshot' ||
        arg.endsWith('/flutter_tools.snapshot'),
  );
  return toolIndex >= 0 &&
      args.skip(toolIndex + 1).any((arg) => arg == 'run' || arg == 'attach');
}

bool _requestPending = false;

void installDesktopDebugHotkeys() {
  if (!kDebugMode || !Platform.isLinux) return;

  HardwareKeyboard.instance.addHandler((event) {
    final keyboard = HardwareKeyboard.instance;
    final focus = FocusManager.instance.primaryFocus?.context;
    final editableFocused = focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null;
    final action = debugHotkeyAction(
      event,
      editableFocused: editableFocused,
      shiftPressed: keyboard.isShiftPressed,
      controlPressed: keyboard.isControlPressed,
      altPressed: keyboard.isAltPressed,
      metaPressed: keyboard.isMetaPressed,
    );
    if (action == null) return false;
    if (!_requestPending) unawaited(_requestFlutterTool(action));
    return true;
  });
}

Future<void> _requestFlutterTool(DebugHotkeyAction action) async {
  _requestPending = true;
  try {
    final parentPid = linuxParentPid(
      await File('/proc/self/stat').readAsString(),
    );
    if (parentPid == null || parentPid <= 1) return;
    final commandLine = await File('/proc/$parentPid/cmdline').readAsString();
    if (!isFlutterToolRunner(commandLine)) {
      debugPrint('Flutter hotkeys require an active flutter run session');
      return;
    }

    final signal = action == DebugHotkeyAction.reload
        ? ProcessSignal.sigusr1
        : ProcessSignal.sigusr2;
    _showDebugHotkeyToast(action);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!Process.killPid(parentPid, signal)) {
      debugPrint('Flutter ${action.name} signal failed');
    }
  } catch (error) {
    debugPrint('Flutter ${action.name} request failed: $error');
  } finally {
    _requestPending = false;
  }
}
