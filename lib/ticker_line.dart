// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

class TickerLine extends StatelessWidget {
  final List<FlSpot> spots;
  final Iterable<DateTime> dates;

  /// ISO 4217 currency the [spots] values are denominated in.
  final String nativeCurrency;

  const TickerLine({
    super.key,
    required this.spots,
    required this.dates,
    this.nativeCurrency = 'USD',
  });

  Widget getBottomTitles(
    double value,
    TitleMeta meta,
    BuildContext context,
    DateFormat formatter,
  ) {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
    Widget text;

    double screenWidth = MediaQuery.of(context).size.width;
    double labelWidth = 120;
    int labelCount = (screenWidth / labelWidth).floor();
    List<int> indices = List.generate(labelCount, (index) {
      return ((spots.length - 1) * index / (labelCount - 1)).round();
    });

    if (indices.contains(value.toInt())) {
      DateTime date = dates.elementAt(value.toInt());
      text = Text(formatter.format(date), style: style);
    } else {
      text = const Text('', style: style);
    }

    return SideTitleWidget(
      meta: meta,
      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Color> gradientColors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.surface,
    ];

    final settings = context.watch<SettingsState>();
    final formatter = DateFormat(settings.dateFormat);

    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 24.0),
      child: LineChart(
        LineChartData(
          clipData: const FlClipData.all(),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 27,
                interval: 1,
                getTitlesWidget: (value, meta) =>
                    getBottomTitles(value, meta, context, formatter),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: Theme.of(context).colorScheme.primary,
              isCurved: settings.curveLines,
              curveSmoothness: settings.curveSmoothness,
              preventCurveOverShooting: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: gradientColors
                      .map((color) => color.withValues(alpha: 0.3))
                      .toList(),
                ),
              ),
            ),
          ],
          gridData: const FlGridData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (touchedSpot) =>
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              getTooltipItems: (touchedSpots) =>
                  getTooltip(touchedSpots, context, formatter),
            ),
          ),
        ),
      ),
    );
  }

  List<LineTooltipItem> getTooltip(
    List<LineBarSpot> touchedSpots,
    BuildContext context,
    DateFormat formatter,
  ) {
    final price = fmtNativeCurrency(touchedSpots.first.y, nativeCurrency);
    final dateStr = dates.elementAtOrNull(touchedSpots.first.x.toInt());
    if (dateStr == null) return [];
    final date = formatter.format(dateStr);

    return [
      LineTooltipItem('$price\n$date', Theme.of(context).textTheme.bodyLarge!),
    ];
  }
}
