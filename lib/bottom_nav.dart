import 'package:flutter/material.dart';
import 'package:frisbee_flutter_foundation/frisbee_flutter_foundation.dart';

/// Total fixed height occupied by the floating dock and its visual padding.
const double bottomNavHeight = PillBottomNav.pillHeight + 32;

class BottomNav extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final void Function(BuildContext, String)? onLongPress;

  const BottomNav({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return PillBottomNav<String>(
      destinations: tabs
          .map(
            (tab) => PillNavDestination(
              value: tab,
              label: _getLabelForTab(tab),
              icon: _getIconForTab(tab),
            ),
          )
          .toList(),
      currentIndex: currentIndex,
      onTap: onTap,
      onLongPress: onLongPress,
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

  String _getLabelForTab(String tab) {
    switch (tab) {
      case 'ChartPage':
        return 'Charts';
      case 'PortfolioPage':
        return 'Portfolio';
      case 'HoldingsPage':
        return 'Holdings';
      default:
        return 'Error';
    }
  }
}
