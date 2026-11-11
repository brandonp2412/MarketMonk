import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';

class ViRebindDialog extends StatefulWidget {
  const ViRebindDialog({
    super.key,
    required this.settings,
    required this.action,
  });

  final SettingsState settings;
  final ViAction action;

  @override
  State<ViRebindDialog> createState() => _ViRebindDialogState();
}

class _ViRebindDialogState extends State<ViRebindDialog> {
  String? _captured;
  bool _handlerInstalled = false;
  bool _reservedKey = false;

  bool _handleKeyEvent(KeyEvent event) {
    final label = viKeyLabelFromEvent(
      event,
      shiftPressed: ViKeyState.instance.shiftPressed,
      otherModifierPressed: ViKeyState.instance.controlPressed ||
          ViKeyState.instance.altPressed ||
          ViKeyState.instance.metaPressed,
    );
    if (label != null) {
      setState(() {
        _reservedKey = viReservedKeys.contains(label) || event.character == '?';
        _captured = _reservedKey ? null : label;
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    ViKeyState.instance.ensureInstalled();
    ViNavigation.instance.capturingBinding = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _handlerInstalled = true;
  }

  @override
  void dispose() {
    ViNavigation.instance.capturingBinding = false;
    if (_handlerInstalled) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        context.l10n.text('Bind {action}', {'action': widget.action.label}),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              switch (true) {
                _ when _reservedKey =>
                  'That key is reserved for navigation or help',
                _ when _captured == null => context.l10n.text('Press a key...'),
                _ => viKeyDisplayName(_captured!),
              },
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text(
                'Use a single letter, number, or symbol. '
                'Shift makes a letter uppercase. f, F, ?, comma and 1–3 are reserved.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('vi-rebind-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          key: const Key('vi-rebind-done'),
          onPressed: _captured == null
              ? null
              : () {
                  final label = _captured!;
                  Navigator.pop(context);
                  unawaited(widget.settings.setViBinding(widget.action, label));
                },
          child: Text(context.l10n.text('Done')),
        ),
      ],
    );
  }
}
