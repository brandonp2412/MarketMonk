import 'package:flutter/material.dart';

/// Distinct series accents derived from the theme, with stable hues by index.
Color chartSeriesColor(ColorScheme colors, int index) {
  final primary = HSLColor.fromColor(colors.primary);
  final dark = colors.brightness == Brightness.dark;
  const hueOffsets = [
    0.0,
    150.0,
    270.0,
    60.0,
    210.0,
    315.0,
    105.0,
    30.0,
    180.0,
    285.0,
    75.0,
    240.0,
  ];
  final hue = (primary.hue +
          hueOffsets[index % hueOffsets.length] +
          (index ~/ hueOffsets.length) * 15) %
      360;
  return HSLColor.fromAHSL(
    1,
    hue,
    primary.saturation.clamp(0.60, 0.85),
    dark
        ? primary.lightness.clamp(0.65, 0.75)
        : primary.lightness.clamp(0.40, 0.48),
  ).toColor();
}
