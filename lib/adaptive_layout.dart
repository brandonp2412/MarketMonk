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

/// Keeps desktop summary metrics legible at desktop and compact widths.
/// Each card must be an [Expanded] widget that fills its row allocation.
Widget desktopMetricGrid({
  required List<Widget> cards,
  required double minCardWidth,
  Key? key,
}) {
  assert(cards.isNotEmpty);
  assert(minCardWidth > 0);
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
      final fullRowWidth =
          minCardWidth * cards.length + gap * (cards.length - 1);
      if (constraints.maxWidth >= fullRowWidth) {
        return row(0, cards.length);
      }
      final columns = cards.length == 5 &&
              constraints.maxWidth >= minCardWidth * 3 + gap * 2
          ? 3
          : 2;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var start = 0; start < cards.length; start += columns) ...[
            if (start > 0) const SizedBox(height: gap),
            row(start, (start + columns).clamp(0, cards.length)),
          ],
        ],
      );
    },
  );
}
