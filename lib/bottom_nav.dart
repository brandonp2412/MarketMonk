import 'package:flutter/material.dart';
import 'package:market_monk/l10n/app_localizations.dart';

/// Total height this floating dock occupies, including its outer padding.
///
/// The dock is 60px high with 16px above and below it. Content that scrolls
/// behind it needs this clearance plus a small visual gap.
const double bottomNavHeight = 92;

/// Bottom clearance for scrollable mobile content so the final item can be
/// scrolled completely above the floating navigation dock.
const double bottomNavScrollClearance = bottomNavHeight + 24;

class BottomNav extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final Function(int) onTap;
  final Function(BuildContext, String)? onLongPress;

  const BottomNav({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, systemBottomInset + 16),
      child: Center(
        heightFactor: 1,
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isSelected = index == currentIndex;
              final label = _getLabelForTab(context, tab);

              return Semantics(
                label: label,
                button: true,
                selected: isSelected,
                excludeSemantics: true,
                child: GestureDetector(
                  key: Key(tab),
                  onTap: () => onTap(index),
                  onLongPress: onLongPress != null
                      ? () => onLongPress!(context, tab)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    height: 48,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? 16 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? color.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getIconForTab(tab),
                          color: isSelected ? color.onPrimary : color.onSurface,
                          size: 24,
                          semanticLabel: label,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          child: isSelected
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(color: color.onPrimary),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  IconData _getIconForTab(String tab) {
    switch (tab) {
      case 'ChartPage':
        return Icons.insights;
      case 'PortfolioPage':
        return Icons.pie_chart;
      case 'HoldingsPage':
        return Icons.list_alt;
      default:
        return Icons.error_rounded;
    }
  }

  String _getLabelForTab(BuildContext context, String tab) {
    switch (tab) {
      case 'ChartPage':
        return context.l10n.text('Charts');
      case 'PortfolioPage':
        return context.l10n.text('Portfolio');
      case 'HoldingsPage':
        return context.l10n.text('Holdings');
      default:
        return context.l10n.text('Error');
    }
  }
}

/// Persistent navigation used when the app has desktop-sized horizontal space.
class DesktopNav extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onSettings;
  final bool compact;

  const DesktopNav({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.onSettings,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: compact ? 80 : 232,
      color: colors.surfaceContainerLow,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            20,
            compact ? 12 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.candlestick_chart_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.candlestick_chart_rounded,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Market Monk',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ...tabs.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _DesktopNavItem(
                        key: Key('desktop-${entry.value}'),
                        icon: _iconForTab(entry.value),
                        label: _labelForTab(context, entry.value),
                        selected: entry.key == currentIndex,
                        compact: compact,
                        onTap: () => onTap(entry.key),
                      ),
                    ),
                  ),
              const Spacer(),
              const Divider(),
              const SizedBox(height: 8),
              _DesktopNavItem(
                icon: Icons.settings_rounded,
                label: context.l10n.text('Settings'),
                compact: compact,
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForTab(String tab) {
    switch (tab) {
      case 'ChartPage':
        return Icons.insights;
      case 'PortfolioPage':
        return Icons.pie_chart;
      case 'HoldingsPage':
        return Icons.list_alt;
      default:
        return Icons.error_rounded;
    }
  }

  String _labelForTab(BuildContext context, String tab) {
    switch (tab) {
      case 'ChartPage':
        return context.l10n.text('Charts');
      case 'PortfolioPage':
        return context.l10n.text('Portfolio');
      case 'HoldingsPage':
        return context.l10n.text('Holdings');
      default:
        return context.l10n.text('Error');
    }
  }
}

class _DesktopNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _DesktopNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant;

    final child = Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: compact
            ? SizedBox(
                height: 48,
                child: Center(child: Icon(icon, size: 22, color: foreground)),
              )
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: foreground),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: foreground,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: compact ? Tooltip(message: label, child: child) : child,
    );
  }
}
