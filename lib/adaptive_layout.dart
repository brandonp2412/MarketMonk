import 'package:flutter/widgets.dart';

/// Minimum width at which Market Monk switches to its desktop navigation shell.
const double desktopLayoutBreakpoint = 840;

/// Desktop windows below this width use the compact icon rail.
const double compactDesktopNavBreakpoint = 1200;

/// Whether the current window should use the desktop layout.
bool isDesktopLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= desktopLayoutBreakpoint;
}
