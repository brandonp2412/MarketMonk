part of '../holdings_page.dart';

class _SymbolTile extends StatelessWidget {
  final SymbolSummary summary;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SymbolTile({
    required this.summary,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final position = summary.position;
    final changePct = position?.change ?? 0.0;
    Widget leadingWidget;
    if (selecting) {
      leadingWidget = SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Checkbox(
            value: isSelected,
            onChanged: (_) => onTap(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    } else {
      leadingWidget = SizedBox(
        width: 40,
        height: 40,
        child: position != null
            ? Icon(
                changePct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                color: changePct >= 0 ? Colors.green : Colors.redAccent,
              )
            : const Icon(Icons.history, color: Colors.grey),
      );
    }

    return ListTile(
      selected: isSelected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.18),
      leading: leadingWidget,
      title: Text(summary.symbol),
      subtitle: position != null
          ? Text(
              '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
              style: TextStyle(
                color: changePct >= 0 ? Colors.green : Colors.redAccent,
                fontSize: 13,
              ),
            )
          : Text(
              '${summary.trades.length} trade(s) — closed position',
              style: const TextStyle(color: Colors.grey),
            ),
      trailing: position != null
          ? Text(
              fmtCurrency(position.currentValue),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
