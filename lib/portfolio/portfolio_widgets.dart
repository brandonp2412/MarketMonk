part of '../portfolio_page.dart';

class _DesktopPortfolioMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color? valueColor;

  const _DesktopPortfolioMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: valueColor ?? theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAllocationRow extends StatelessWidget {
  final Color color;
  final String symbol;
  final String name;
  final double value;
  final double allocationPct;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopAllocationRow({
    required this.color,
    required this.symbol,
    required this.name,
    required this.value,
    required this.allocationPct,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DesktopContextMenu(
      actionsBuilder: () => symbol == 'CASH'
          ? Future.value(<DesktopMenuAction>[])
          : tickerContextActions(context, symbol),
      copyText:
          '$symbol $name ${fmtCurrency(value)} (${allocationPct.toStringAsFixed(2)}%)',
      copyLabel: context.l10n.text('Copy allocation'),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(symbol)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtCurrency(value),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '${allocationPct.toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopReturnRow extends StatelessWidget {
  final Position position;
  final PortfolioReturn? periodReturn;
  final VoidCallback onTap;

  const _DesktopReturnRow({
    required this.position,
    required this.periodReturn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = periodReturn?.percent ?? double.nan;
    final positive = change >= 0;
    final color = positive ? Colors.green : Colors.redAccent;
    final pnl = periodReturn?.gain ?? double.nan;

    return DesktopContextMenu(
      actionsBuilder: () => tickerContextActions(context, position.symbol),
      copyText:
          '${position.symbol} ${pnl.isFinite ? fmtCurrency(pnl) : 'Unavailable'}',
      copyLabel: 'Copy holding return',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('desktop-return-${position.symbol}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Row(
              children: [
                Icon(
                  positive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 11),
                Expanded(child: Text(position.symbol)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pnl.isFinite
                          ? (pnl >= 0 ? '+' : '') + fmtCurrency(pnl)
                          : 'Unavailable',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: pnl >= 0 ? Colors.green : Colors.redAccent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      change.isFinite
                          ? '${positive ? '+' : ''}${change.toStringAsFixed(2)}%'
                          : '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PieHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  const _PieHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(covariant _PieHeaderDelegate oldDelegate) =>
      child != oldDelegate.child ||
      backgroundColor != oldDelegate.backgroundColor;
}

class _SummaryCard extends StatelessWidget {
  final String displayTotal;
  final String totalLabel;
  final double totalGain;
  final double totalGainPct;
  final VoidCallback onExport;
  final VoidCallback onShare;

  const _SummaryCard({
    required this.displayTotal,
    required this.totalLabel,
    required this.totalGain,
    required this.totalGainPct,
    required this.onExport,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final gainColor = totalGain >= 0 ? Colors.green : Colors.redAccent;
    final settings = context.watch<SettingsState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            ProfilePicker(
              key: const Key('portfolio-profile-picker'),
              onExport: onExport,
              onShare: _supportsFileSharing ? onShare : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(totalLabel, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  displayTotal,
                  key: const Key('portfolio-total-value'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  totalGain.isFinite
                      ? '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                          '  (${totalGainPct.toStringAsFixed(2)}%)'
                      : 'Return history unavailable',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: gainColor),
                ),
              ],
            ),
            const Spacer(),
            if (settings.visibleCurrencies.length > 1)
              PopupMenuButton<String>(
                key: const Key('portfolio-currency-menu'),
                onSelected: (value) => runDetachedTask(
                  settings.setDisplayCurrency(value),
                  'Failed to change display currency',
                ),
                itemBuilder: (_) => [
                  for (final currencyCode in settings.visibleCurrencies)
                    CheckedPopupMenuItem(
                      value: currencyCode,
                      checked: currencyCode == settings.displayCurrency,
                      child: Text(currencyCode),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(settings.displayCurrency),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendTile extends StatelessWidget {
  final Color color;
  final String symbol;
  final String name;
  final double value;
  final double allocationPct;
  final double changePct;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _LegendTile({
    required this.color,
    required this.symbol,
    required this.name,
    required this.value,
    required this.allocationPct,
    required this.changePct,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopContextMenu(
      actionsBuilder: () => symbol == 'CASH'
          ? Future.value(<DesktopMenuAction>[])
          : tickerContextActions(context, symbol),
      copyText:
          '$symbol $name ${fmtCurrency(value)} (${allocationPct.toStringAsFixed(2)}%)',
      copyLabel: context.l10n.text('Copy allocation'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0),
        onTap: onTap,
        selected: isHighlighted,
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(symbol),
        subtitle: Text('${allocationPct.toStringAsFixed(1)}%'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtCurrency(value),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: switch (true) {
                      _ when !changePct.isFinite =>
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      _ when changePct >= 0 => Colors.green,
                      _ => Colors.redAccent,
                    },
                  ),
            ),
            Text(
              changePct.isFinite
                  ? '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%'
                  : '—',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: switch (true) {
                      _ when !changePct.isFinite =>
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      _ when changePct >= 0 => Colors.green,
                      _ => Colors.redAccent,
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
