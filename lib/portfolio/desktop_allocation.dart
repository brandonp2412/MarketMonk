part of '../portfolio_page.dart';

extension _PortfolioDesktopAllocation on PortfolioPageState {
  Widget _buildDesktopAllocationChart({
    required List<MarketDonutSlice> slices,
    required List<PortfolioAllocation> sorted,
    required int? selectedIndex,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (slices.isEmpty)
          const Text('No holdings on this date')
        else
          MarketDonutChart(
            slices: slices,
            selectedIndex: selectedIndex,
            onSelectionChanged: (index) {
              if (index == touchedIndex) return;
              _updateState(() => touchedIndex = index);
            },
            centerSpaceRadius: compact ? 48 : 72,
            radius: compact ? 54 : 75,
            selectedRadius: compact ? 60 : 90,
          ),
        if (slices.isNotEmpty)
          IgnorePointer(
            child: SizedBox(
              width: compact ? 108 : 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedIndex == null
                        ? context.l10n.text('Holdings')
                        : sorted[selectedIndex].symbol,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selectedIndex == null
                        ? '${sorted.length} ${context.l10n.text('positions')}'
                        : fmtCurrency(sorted[selectedIndex].value),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
