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
  final List<MarketCandlePoint> candles;
  final bool showCandlesticks;
  final ValueNotifier<int?>? candleSelection;

  /// Overlays a trailing average of up to 20 price observations.
  final bool showRollingAverage;

  /// Inclusive columns selected by the chart's parent.
  final (int, int)? range;

  /// Notifies the parent when the visible period changes or is reset.
  final ValueChanged<(int, int)?>? onRangeChanged;
  final bool pickRange;

  /// ISO 4217 currency the [spots] values are denominated in.
  final String nativeCurrency;

  /// Includes local clock time in labels for timestamped intraday bars.
  final bool intraday;
  final DateTime? requestedStartDate;

  /// Shows the grid and axes for the requested period without prices.
  final bool loading;

  const TickerLine({
    super.key,
    required this.spots,
    required this.dates,
    this.candles = const [],
    this.showCandlesticks = false,
    this.candleSelection,
    this.nativeCurrency = 'USD',
    this.intraday = false,
    this.requestedStartDate,
    this.loading = false,
    this.showRollingAverage = false,
    this.range,
    this.onRangeChanged,
    this.pickRange = false,
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
    final tooltipFormatter = DateFormat(
      intraday ? "${settings.dateFormat} HH:mm" : settings.dateFormat,
    );
    final axisFormatter = DateFormat(intraday ? 'HH:mm' : settings.dateFormat);
    final colorScheme = Theme.of(context).colorScheme;
    final datesList = dates.toList();
    final candlesByColumn = {
      for (final candle in candles) candle.column: candle,
    };
    final chartStart = intraday ? null : requestedStartDate;
    final chartEnd = DateUtils.dateOnly(DateTime.now());
    List<String> labels;
    List<double>? datePositions;
    if (loading) {
      if (chartStart == null) {
        labels = const [];
      } else {
        final start = DateUtils.dateOnly(chartStart);
        final days = chartEnd.difference(start).inDays.clamp(0, 10 * 366);
        labels = [
          for (var day = 0; day <= days; day++)
            axisFormatter.format(start.add(Duration(days: day))),
        ];
        datePositions = [
          for (var day = 0; day <= days; day++) day.toDouble(),
        ];
      }
    } else {
      labels = [for (final date in datesList) axisFormatter.format(date)];
      datePositions = chartStart == null
          ? null
          : [
              for (final date in datesList)
                date.difference(chartStart).inMinutes / Duration.minutesPerDay,
            ];
    }

    return Column(
      children: [
        Expanded(
          child: MarketLineChart(
            range: range,
            showRollingAverage: showRollingAverage,
            onRangeChanged: onRangeChanged,
            pickRange: pickRange,
            series: [
              MarketLineChartSeries(
                points: datePositions == null
                    ? spots
                    : [
                        for (var index = 0; index < spots.length; index++)
                          MarketLineChartPoint(
                            datePositions[index],
                            spots[index].y,
                            column: spots[index].column,
                            comparisonValue: spots[index].comparisonValue,
                          ),
                      ],
                color: colorScheme.primary,
                name: nativeCurrency,
                fill: true,
                strokeWidth: 3,
              ),
            ],
            xLabels: labels,
            pointCount: spots.length,
            xAxisPositions: datePositions,
            loading: loading,
            xAxisBounds: !loading || chartStart == null
                ? null
                : (
                    0.0,
                    (chartEnd.difference(chartStart).inMinutes /
                            Duration.minutesPerDay)
                        .clamp(1.0, double.infinity),
                  ),
            candles: candles,
            showCandlesticks: showCandlesticks,
            candleSelection: candleSelection,
            candleTooltipTitle: showCandlesticks
                ? (index) => index < datesList.length
                    ? tooltipFormatter.format(datesList[index])
                    : ''
                : null,
            candleTooltipRows: showCandlesticks
                ? (index) {
                    final candle = candlesByColumn[index];
                    if (candle == null) return const <String>[];
                    return [
                      'O ${fmtNativeCurrency(candle.open, nativeCurrency)}   H ${fmtNativeCurrency(candle.high, nativeCurrency)}',
                      'L ${fmtNativeCurrency(candle.low, nativeCurrency)}   C ${fmtNativeCurrency(candle.close, nativeCurrency)}',
                    ];
                  }
                : null,
            yLabelFormatter: (value) =>
                fmtCompactNativeCurrency(value, nativeCurrency),
            tooltipRowLabel: (PlotMark mark) =>
                tooltipTextAt(mark.index, tooltipFormatter),
            curveLines: settings.curveLines,
            curveSmoothness: settings.curveSmoothness,
            showGridlines: settings.showChartGridlines,
            fillChartArea: settings.fillChartArea,
            leftInset: 64,
            accessibilityLabel: 'Price history',
            accessibilityValue: loading
                ? 'Loading prices'
                : spots.isEmpty
                    ? 'No prices'
                    : '${spots.length} price points',
          ),
        ),
      ],
    );
  }
}
