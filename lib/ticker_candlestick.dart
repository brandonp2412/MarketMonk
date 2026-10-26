import 'dart:math';

import 'package:drafter/drafter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/utils.dart';

@immutable
class PriceCandle {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  const PriceCandle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  bool get isValid =>
      [open, high, low, close].every((value) => value.isFinite && value > 0) &&
      high >= max(open, close) &&
      low <= min(open, close) &&
      high >= low;
}

List<PriceCandle> aggregatePriceCandles(
  List<PriceCandle> source,
  int maxCount,
) {
  final candles = source.where((candle) => candle.isValid).toList();
  if (candles.length <= maxCount || maxCount < 1) return candles;
  final groupSize = (candles.length / maxCount).ceil();
  return [
    for (var start = 0; start < candles.length; start += groupSize)
      _aggregateGroup(
        candles.sublist(start, min(start + groupSize, candles.length)),
      ),
  ];
}

PriceCandle _aggregateGroup(List<PriceCandle> candles) => PriceCandle(
      date: candles.first.date,
      open: candles.first.open,
      high: candles.map((candle) => candle.high).reduce(max),
      low: candles.map((candle) => candle.low).reduce(min),
      close: candles.last.close,
    );

class TickerCandlestick extends StatelessWidget {
  final List<PriceCandle> candles;
  final String nativeCurrency;
  final bool intraday;
  final bool showRollingAverage;

  const TickerCandlestick({
    super.key,
    required this.candles,
    required this.nativeCurrency,
    this.intraday = false,
    this.showRollingAverage = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = colorScheme.primary;
    final chartTheme = DrafterThemeColors(
      palette: DrafterColors.palette,
      grid: colorScheme.onSurface.withValues(alpha: 0.07),
      label: colorScheme.onSurface.withValues(alpha: 0.62),
      surface: colorScheme.surface,
      isDark: dark,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final plotted = aggregatePriceCandles(
          candles,
          max(1, (width / 8).floor()),
        );
        final dateFormat = DateFormat(
          intraday
              ? 'HH:mm'
              : candles.length > 400
                  ? 'MMM yy'
                  : 'd/M',
        );
        final rows = [
          for (final candle in plotted)
            Candle(
              label: dateFormat.format(candle.date),
              open: candle.open,
              high: candle.high,
              low: candle.low,
              close: candle.close,
            ),
        ];

        if (rows.isEmpty) {
          return const Center(child: Text('No OHLC prices available'));
        }

        return DrafterTheme(
          colors: chartTheme,
          child: InteractiveChart(
            renderer: CandlestickChartRenderer(
              candles: rows,
              movingAverages: [
                if (showRollingAverage) MovingAverage(period: 20, color: color),
              ],
            ),
            animate: false,
            interaction: ChartInteraction(
              rowLabel: (mark) {
                final candle = plotted[mark.index];
                String fmt(double value) =>
                    fmtCompactNativeCurrency(value, nativeCurrency);
                return 'O ${fmt(candle.open)} · H ${fmt(candle.high)} · '
                    'L ${fmt(candle.low)} · C ${fmt(candle.close)}';
              },
            ),
          ),
        );
      },
    );
  }
}
