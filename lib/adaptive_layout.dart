import 'package:flutter/material.dart';

/// Minimum width at which Market Monk switches to its desktop navigation shell.
const double desktopLayoutBreakpoint = 840;

/// Whether the current window should use the desktop layout.
bool isDesktopLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= desktopLayoutBreakpoint;
}

/// Creates a material route that transitions instantly on desktop layouts.
PageRoute<T> adaptivePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (!isDesktopLayout(context)) {
    return MaterialPageRoute<T>(builder: builder);
  }
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

/// Keeps desktop summary metrics legible by switching from four cards to two rows.
/// Each card must be an [Expanded] widget that fills its row allocation.
Widget desktopMetricGrid({
  required List<Widget> cards,
  required double minCardWidth,
  Key? key,
}) {
  assert(cards.length == 4);
  const gap = 12.0;

  Widget row(int from, int to) => Row(
        children: [
          for (var index = from; index < to; index++) ...[
            if (index > from) const SizedBox(width: gap),
            cards[index],
          ],
        ],
      );

  return LayoutBuilder(
    key: key,
    builder: (context, constraints) {
      if (constraints.maxWidth >= minCardWidth * 4 + gap * 3) {
        return row(0, 4);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(0, 2),
          const SizedBox(height: gap),
          row(2, 4),
        ],
      );
    },
  );
}
