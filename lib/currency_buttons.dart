import 'package:flutter/material.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

class CurrencyButtons extends StatelessWidget {
  const CurrencyButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    if (settings.visibleCurrencies.length < 2) {
      return const SizedBox.shrink();
    }

    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      segments: [
        for (final code in settings.visibleCurrencies)
          ButtonSegment<String>(value: code, label: Text(code)),
      ],
      selected: {settings.displayCurrency},
      onSelectionChanged: (selection) {
        final code = selection.first;
        if (code == settings.displayCurrency) return;
        runDetachedTask(
          settings.setDisplayCurrency(code),
          'Failed to change display currency',
        );
      },
    );
  }
}
