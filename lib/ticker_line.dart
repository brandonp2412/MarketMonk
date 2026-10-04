// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:drafter/drafter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

class TickerLine extends StatelessWidget {
  final List<MarketLineChartPoint> spots;
  final Iterable<DateTime> dates;

  /// ISO 4217 currency the [spots] values are denominated in.
  final String nativeCurrency;

  const TickerLine({
    super.key,
    required this.spots,
    required this.dates,
    this.nativeCurrency = 'USD',
  });

  String tooltipTextAt(int index, DateFormat formatter) {
    if (index < 0 || index >= spots.length) return '';
    final date = dates.elementAtOrNull(index);
    if (date == null) return '';
    final price = fmtNativeCurrency(spots[index].y, nativeCurrency);
    return '$price · ${formatter.format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final formatter = DateFormat(settings.dateFormat);
    final colorScheme = Theme.of(context).colorScheme;
    final labels = [for (final date in dates) formatter.format(date)];

    return MarketLineChart(
      series: [
        MarketLineChartSeries(
          points: spots,
          color: colorScheme.primary,
          name: nativeCurrency,
          fill: true,
          strokeWidth: 3,
        ),
      ],
      xLabels: labels,
      pointCount: spots.length,
      yLabelFormatter: (value) =>
          fmtCompactNativeCurrency(value, nativeCurrency),
      tooltipRowLabel: (PlotMark mark) => tooltipTextAt(mark.index, formatter),
      curveLines: settings.curveLines,
      curveSmoothness: settings.curveSmoothness,
      leftInset: 64,
      accessibilityLabel: 'Price history',
      accessibilityValue:
          spots.isEmpty ? 'No prices' : '${spots.length} price points',
    );
  }
}
