import 'dart:async';
import 'dart:math';

import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/portfolio_chart_scale.dart';

part 'chart/chart_interaction.dart';
part 'chart/chart_renderer.dart';
part 'chart/tooltip_painting.dart';

/// A chart value that can retain its absolute value for range comparisons.
@immutable
class MarketLineChartPoint {
  final double x;
  final double y;
  final int? column;

  /// Absolute value used to rebase percentage comparisons when the range changes.
  final double? comparisonValue;

  const MarketLineChartPoint(
    this.x,
    this.y, {
    this.column,
    this.comparisonValue,
  });
}

@immutable
class MarketLineChartSeries {
  final List<MarketLineChartPoint> points;
  final Color color;
  final String name;
  final bool fill;
  final double strokeWidth;

  const MarketLineChartSeries({
    required this.points,
    required this.color,
    this.name = '',
    this.fill = true,
    this.strokeWidth = 3,
  });
}

@immutable
class MarketCandlePoint {
  final int column;
  final int seriesIndex;
  final bool sampled;
  final double open;
  final double high;
  final double low;
  final double close;

  const MarketCandlePoint({
    required this.column,
    this.seriesIndex = 0,
    this.sampled = false,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

@immutable
class _LineChartAxisLabel {
  final double x;
  final int? column;
  final String text;

  const _LineChartAxisLabel(this.x, this.text, {this.column});
}

const _lineChartEdgePaddingFraction = 0.02;
const _axisLabelFontSize = 12.0;
const _xAxisLabelMinGap = 12.0;
const _chartTopInset = 24.0;
const _chartBottomLabelInset = 38.0;
const _tooltipPadding = 8.0;
const _tooltipRowHeight = 16.0;
const _tooltipDotGap = 12.0;
const _tooltipFontSize = 10.0;
const _tooltipSwatchSize = 8.0;
const _tooltipSwatchGap = 6.0;
const _activeDotRadius = 6.0;

class MarketLineChart extends StatelessWidget {
  final List<MarketLineChartSeries> series;
  final List<String> xLabels;
  final int pointCount;
  final List<double>? xAxisPositions;
  final (double, double)? xAxisBounds;
  final List<MarketCandlePoint> candles;
  final bool showCandlesticks;
  final ValueNotifier<int?>? candleSelection;
  final String Function(int index)? candleTooltipTitle;
  final List<String> Function(int index)? candleTooltipRows;
  final String Function(double value) yLabelFormatter;
  final String Function(PlotMark mark) tooltipRowLabel;
  final bool curveLines;

  /// Replaces each series with its trailing average of up to 20 observations.
  final bool showRollingAverage;
  final double curveSmoothness;
  final bool showGridlines;
  final bool fillChartArea;
  final double leftInset;
  final String accessibilityLabel;
  final String? accessibilityValue;

  /// Selected inclusive columns, retained by the caller across data changes.
  final (int, int)? range;

  /// Updates the caller-owned [range]; null restores the full period.
  final ValueChanged<(int, int)?>? onRangeChanged;
  final bool pickRange;

  /// Renders the grid and axes without price values.
  final bool loading;

  const MarketLineChart({
    super.key,
    required this.series,
    required this.xLabels,
    required this.pointCount,
    this.xAxisPositions,
    this.xAxisBounds,
    this.candles = const [],
    this.showCandlesticks = false,
    this.candleSelection,
    this.candleTooltipTitle,
    this.candleTooltipRows,
    required this.yLabelFormatter,
    required this.tooltipRowLabel,
    required this.curveLines,
    this.showRollingAverage = false,
    required this.curveSmoothness,
    this.showGridlines = false,
    this.fillChartArea = true,
    this.leftInset = 64,
    this.accessibilityLabel = 'Price chart',
    this.accessibilityValue,
    this.range,
    this.onRangeChanged,
    this.pickRange = false,
    this.loading = false,
  });

  @visibleForTesting
  static List<int> xAxisLabelCandidates(int count, double width) {
    if (count <= 0) return const [];
    final limit = max(
      2,
      (width / (_axisLabelFontSize + _xAxisLabelMinGap)).ceil() * 2,
    );
    final candidates = min(count, limit);
    if (candidates == 1) return const [0];
    return [
      for (var index = 0; index < candidates; index++)
        (index * (count - 1) / (candidates - 1)).round(),
    ];
  }

  @visibleForTesting
  static List<int> selectXAxisLabelIndices(
    List<double> centers,
    List<double> widths,
    double minGap,
  ) {
    final count = centers.length;
    if (count == 0) return const [];
    if (count == 1) return const [0];

    final order = List<int>.generate(count, (index) => index)
      ..sort((a, b) => centers[a].compareTo(centers[b]));
    final first = order.first;
    final last = order.last;
    final lastLeft = centers[last] - widths[last] / 2;

    final packed = <int>[first];
    var lastRight = centers[first] + widths[first] / 2;
    for (final index in order.skip(1).take(count - 2)) {
      final left = centers[index] - widths[index] / 2;
      final right = centers[index] + widths[index] / 2;
      if (left < lastRight + minGap || right + minGap > lastLeft) continue;
      packed.add(index);
      lastRight = right;
    }
    packed.add(last);

    if (packed.length <= 2 || packed.length == count) {
      packed.sort();
      return packed;
    }

    final balanced = <int>[first];
    var previousOrderPosition = 0;
    final span = centers[last] - centers[first];
    for (var slot = 1; slot < packed.length - 1; slot++) {
      final target = centers[first] + span * slot / (packed.length - 1);
      final remainingSlots = packed.length - 1 - slot;
      final maxOrderPosition = order.length - 1 - remainingSlots;
      var bestOrderPosition = -1;
      var bestDistance = double.infinity;
      for (var position = previousOrderPosition + 1;
          position <= maxOrderPosition;
          position++) {
        final index = order[position];
        final previous = balanced.last;
        final left = centers[index] - widths[index] / 2;
        final previousRight = centers[previous] + widths[previous] / 2;
        if (left < previousRight + minGap) continue;
        final distance = (centers[index] - target).abs();
        if (distance <= bestDistance) {
          bestDistance = distance;
          bestOrderPosition = position;
        }
      }
      if (bestOrderPosition < 0) {
        packed.sort();
        return packed;
      }
      balanced.add(order[bestOrderPosition]);
      previousOrderPosition = bestOrderPosition;
    }
    balanced.add(last);
    for (var i = 1; i < balanced.length; i++) {
      final previous = balanced[i - 1];
      final current = balanced[i];
      final gap = centers[current] -
          widths[current] / 2 -
          (centers[previous] + widths[previous] / 2);
      if (gap < minGap) {
        packed.sort();
        return packed;
      }
    }
    balanced.sort();
    return balanced;
  }

  @visibleForTesting
  static double tooltipTopForMarks(
    List<double> markYs, {
    required int rowCount,
    bool hasTitle = false,
  }) {
    if (markYs.isEmpty) return 0;
    final tooltipHeight = (hasTitle ? _tooltipRowHeight : 0) +
        rowCount * _tooltipRowHeight +
        _tooltipPadding * 2;
    return markYs.reduce(min) - tooltipHeight - _tooltipDotGap;
  }

  @override
  Widget build(BuildContext context) {
    final axisLabelColor = Theme.of(context).colorScheme.onSurface;
    final points = [for (final line in series) ...line.points];
    final candleBoundsPoints = [
      ...points,
      for (final candle in candles) ...[
        MarketLineChartPoint(candle.column.toDouble(), candle.high),
        MarketLineChartPoint(candle.column.toDouble(), candle.low),
      ],
    ];
    final yBounds = _calculateYBounds(candleBoundsPoints);
    return _MarketLineChartInteraction(
      renderer: _MarketLineChartRenderer(
        series: series,
        candles: candles,
        loading: loading,
        showCandlesticks: showCandlesticks,
        minY: yBounds.$1,
        maxY: yBounds.$2,
        curveLines: curveLines,
        showRollingAverage: showRollingAverage,
        curveSmoothness: curveSmoothness,
        showGridlines: showGridlines,
        fillChartArea: fillChartArea,
        xLabels: [
          for (var i = 0; i < xLabels.length; i++)
            _LineChartAxisLabel(
              xAxisPositions?[i] ?? i.toDouble(),
              xLabels[i],
              column: i,
            ),
        ],
        uniformXCount: xAxisPositions == null ? pointCount : null,
        xAxisBounds: xAxisBounds,
        axisLabelColor: axisLabelColor,
        yLabelFormatter: yLabelFormatter,
        leftInset: leftInset,
        accessibilityLabel: accessibilityLabel,
        accessibilityValue: accessibilityValue,
      ),
      rowLabel: tooltipRowLabel,
      candleTooltipTitle: showCandlesticks ? candleTooltipTitle : null,
      candleTooltipRows: showCandlesticks ? candleTooltipRows : null,
      stickyTooltip: showCandlesticks,
      externalSelection: candleSelection,
      range: range,
      onRangeChanged: onRangeChanged,
      pickRange: pickRange,
    );
  }
}
