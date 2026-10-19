import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/chart_colors.dart';

void main() {
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
