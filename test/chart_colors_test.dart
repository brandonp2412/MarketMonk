import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/chart_colors.dart';

void main() {
  test('series palette stays balanced and distinct across 12 series', () {
    final warmTheme = ColorScheme.fromSeed(seedColor: const Color(0xFF8A5F16));
    final coolTheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final palette = [
      for (var i = 0; i < 12; i++) chartSeriesColor(warmTheme, i),
    ];

    expect(palette.toSet(), hasLength(12));
    for (var i = 0; i < 12; i++) {
      expect(chartSeriesColor(coolTheme, i), palette[i]);
      expect(HSLColor.fromColor(palette[i]).saturation, lessThan(0.7));
    }
    expect(chartSeriesColor(warmTheme, 12), isNot(palette.first));
  });

  test('dark theme chart accents are lighter but preserve their hues', () {
    final light = ColorScheme.fromSeed(seedColor: Colors.teal);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );

    for (var i = 0; i < 12; i++) {
      final lightHsl = HSLColor.fromColor(chartSeriesColor(light, i));
      final darkHsl = HSLColor.fromColor(chartSeriesColor(dark, i));
      expect(darkHsl.lightness, greaterThan(lightHsl.lightness));
      expect((darkHsl.hue - lightHsl.hue).abs(), lessThan(6));
    }
  });
  test('portfolio holdings reuse the corresponding favorite chart colors', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    const favorites = ['MSFT', 'AAPL'];
    final colors = portfolioHoldingColors(
      scheme,
      ['AAPL', 'OTHER', 'MSFT'],
      accountCount: 2,
      favorites: favorites,
    );

    expect(colors[0], chartSeriesColor(scheme, 3));
    expect(colors[2], chartSeriesColor(scheme, 2));
    expect(colors[1], chartSeriesColor(scheme, 0));
    expect(colors.toSet(), hasLength(3));
  });

  test('holdings without favorites use the chart line palette', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final colors = portfolioHoldingColors(
      scheme,
      ['AAPL', 'MSFT'],
      accountCount: 1,
      favorites: const [],
    );
    expect(colors, [chartSeriesColor(scheme, 0), chartSeriesColor(scheme, 1)]);
  });
}
