import 'package:flutter/widgets.dart';

class ViTarget {
  const ViTarget({
    required this.requestSearch,
    required this.moveFocus,
    this.toggleSelect,
    this.deleteFocus,
    this.undoDelete,
    this.halfPageUp,
    this.halfPageDown,
  });

  final VoidCallback requestSearch;

  final void Function(int delta) moveFocus;

  final VoidCallback? toggleSelect;

  final VoidCallback? deleteFocus;

  final VoidCallback? undoDelete;

  final VoidCallback? halfPageUp;

  final VoidCallback? halfPageDown;
}

final class ViNavigation {
  ViNavigation._();

  static final instance = ViNavigation._();

  ViTarget? target;
  VoidCallback? fallbackSearch;
}

/// Focus index after moving [delta] from [current] in a list of [length]
/// rows. Returns -1 when the list is empty.
int viFocusIndex(int current, int delta, int length) {
  if (length == 0) return -1;
  if (current < 0) return delta < 0 ? length - 1 : 0;
  return (current + delta).clamp(0, length - 1);
}

/// Tracks how many routes sit on top of the app's initial route. The
/// initial route is itself a [ModalRoute], so its push and pop are ignored
/// to keep the depth at 0 while no dialog or page is open.
final class ModalRouteTracker extends NavigatorObserver {
  ModalRouteTracker._();

  static final instance = ModalRouteTracker._();

  int modalDepth = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is ModalRoute && previousRoute != null) modalDepth += 1;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is ModalRoute && previousRoute != null) {
      modalDepth = (modalDepth - 1).clamp(0, 99);
    }
  }
}
