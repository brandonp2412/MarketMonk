// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class TickerLine extends StatelessWidget {
  final DateFormat formatter;
  final List<FlSpot> spots;
  final Iterable<DateTime> dates;

  const TickerLine({
    super.key,
    required this.formatter,
    required this.spots,
    required this.dates,
  });

  Widget getBottomTitles(
    double value,
    TitleMeta meta,
    BuildContext context,
  ) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
    );
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
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 32.0, top: 16.0),
      child: SizedBox(
        height: 350,
        child: LineChart(
          LineChartData(
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 45),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 27,
                  interval: 1,
                  getTitlesWidget: (value, meta) =>
                      getBottomTitles(value, meta, context),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Theme.of(context).colorScheme.primary,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(
                    radius: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (touchedSpot) =>
                    Theme.of(context).colorScheme.surface,
                getTooltipItems: (touchedSpots) =>
                    getTooltip(touchedSpots, context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<LineTooltipItem> getTooltip(
    List<LineBarSpot> touchedSpots,
    BuildContext context,
  ) {
    final price = '\$${touchedSpots.first.y.toStringAsFixed(2)}';
    final date = formatter.format(
      dates.elementAt(touchedSpots.first.x.toInt()),
    );
    return [
      LineTooltipItem(
        '$price\n$date',
        Theme.of(context).textTheme.bodyLarge!,
      ),
    ];
  }
}
