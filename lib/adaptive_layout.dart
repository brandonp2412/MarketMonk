import 'package:flutter/material.dart';

/// Minimum width at which Market Monk switches to its desktop navigation shell.
const double desktopLayoutBreakpoint = 840;

const desktopPagePadding = EdgeInsets.fromLTRB(32, 28, 32, 24);
const desktopMetricPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 16);
const desktopMetricRadius = 14.0;

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

  Widget row(int from, int to) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = from; index < to; index++) ...[
              if (index > from) const SizedBox(width: gap),
              cards[index],
            ],
          ],
        ),
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

class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

AppBar adaptiveAppBar(
  BuildContext context, {
  required String title,
  Widget? leading,
  PreferredSizeWidget? bottom,
}) {
  if (!isDesktopLayout(context)) {
    return AppBar(title: Text(title), leading: leading, bottom: bottom);
  }
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: desktopPagePadding.top + 64 + 24,
    titleSpacing: desktopPagePadding.left,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    title: Padding(
      padding: EdgeInsets.only(top: desktopPagePadding.top - 24),
      child: DesktopPageHeader(
        title: title,
        leading: leading ?? (canPop ? const BackButton() : null),
      ),
    ),
    bottom: bottom,
  );
}
