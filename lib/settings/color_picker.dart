import 'package:flutter/material.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/theme_color_picker.dart';
import 'package:market_monk/utils.dart';

class SettingsColorPicker extends StatelessWidget {
  static const _colors = [
    defaultSeedColor,
    Color(0xFF2B7A78),
    Color(0xFF6750A4),
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFD32F2F),
    Color(0xFFF57C00),
    Color(0xFF7B1FA2),
    Color(0xFF0097A7),
    Color(0xFF5D4037),
    Color(0xFF455A64),
  ];

  final SettingsState settings;

  const SettingsColorPicker({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final custom = !_colors.contains(settings.seedColor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('App color'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in _colors)
                _colorSwatch(
                  context,
                  color: color,
                  selected: settings.seedColor == color,
                  onTap: () => runDetachedTask(
                    settings.setSeedColor(color),
                    'Failed to save theme color',
                  ),
                ),
              _colorSwatch(
                context,
                color: custom
                    ? settings.seedColor
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                selected: custom,
                custom: true,
                onTap: () async {
                  final selected =
                      await showThemeColorPicker(context, settings.seedColor);
                  if (selected != null) {
                    runDetachedTask(
                      settings.setSeedColor(selected),
                      'Failed to save custom theme color',
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _colorSwatch(
  BuildContext context, {
  required Color color,
  required bool selected,
  required VoidCallback onTap,
  bool custom = false,
}) {
  final label = custom
      ? context.l10n.text('Custom color')
      : '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  return Tooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkWell(
        key: Key(
          custom ? 'theme-color-custom' : 'theme-color-${color.toARGB32()}',
        ),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected || custom
              ? Icon(
                  custom ? Icons.colorize_rounded : Icons.check_rounded,
                  size: 19,
                  color: color.computeLuminance() > 0.45
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    ),
  );
}
