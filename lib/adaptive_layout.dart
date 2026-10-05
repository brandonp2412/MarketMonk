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
