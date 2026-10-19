import 'package:flutter/material.dart';

/// Consistent categorical accents for both charts and portfolio holdings.
const _seriesPalette = <Color>[
  Color(0xFF3E78A8),
  Color(0xFFD58B43),
  Color(0xFF269A94),
  Color(0xFF9271B0),
  Color(0xFFC9686E),
  Color(0xFF659447),
  Color(0xFFB36A9B),
  Color(0xFF4C9FC2),
  Color(0xFFAD8C45),
  Color(0xFF6269A3),
  Color(0xFFB86A4D),
  Color(0xFF527E79),
];

Color chartSeriesColor(ColorScheme colors, int index) {
  final base = _seriesPalette[index % _seriesPalette.length];
  final cycle = index ~/ _seriesPalette.length;
  final Color accent;
  if (cycle == 0) {
    accent = base;
  } else {
    final hsl = HSLColor.fromColor(base);
    accent = hsl
        .withHue((hsl.hue + cycle * 18) % 360)
        .withLightness(
          (hsl.lightness + (cycle.isOdd ? 0.09 : -0.07)).clamp(0.3, 0.7),
        )
        .toColor();
  }
  return colors.brightness == Brightness.dark
      ? Color.lerp(accent, Colors.white, 0.2)!
      : accent;
}

List<Color> portfolioHoldingColors(
  ColorScheme scheme,
  List<String> symbols, {
  required int accountCount,
  required List<String> favorites,
}) {
  final favoriteIndices = [
    for (final symbol in symbols)
      favorites.indexWhere(
        (favorite) => favorite.toUpperCase() == symbol.toUpperCase(),
      ),
  ];
  final reserved = <int>{
    for (final index in favoriteIndices)
      if (index >= 0) accountCount + index,
  };
  var nextIndex = 0;
  final paletteIndices = <int>[];
  for (final favoriteIndex in favoriteIndices) {
    if (favoriteIndex >= 0) {
      paletteIndices.add(accountCount + favoriteIndex);
    } else {
      while (reserved.contains(nextIndex)) {
        nextIndex++;
      }
      paletteIndices.add(nextIndex++);
    }
  }
  return [for (final index in paletteIndices) chartSeriesColor(scheme, index)];
}
