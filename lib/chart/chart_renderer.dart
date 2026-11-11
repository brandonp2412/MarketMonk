part of '../market_line_chart.dart';

class _MarketLineTooltipPainter extends CustomPainter {
  final ValueNotifier<int?> activeIndex;
  final ChartScene scene;
  final DrafterThemeColors theme;
  final String Function(PlotMark mark) rowLabel;
  final String Function(int index)? candleTooltipTitle;
  final List<String> Function(int index)? candleTooltipRows;

  _MarketLineTooltipPainter({
    required this.activeIndex,
    required this.scene,
    required this.theme,
    required this.rowLabel,
    this.candleTooltipTitle,
    this.candleTooltipRows,
  }) : super(repaint: activeIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final index = activeIndex.value;
    final bounds = scene.bounds;
    if (index == null || bounds == null) return;

    final marks = ChartHitTest.marksAtIndex(scene, index);
    if (marks.isEmpty) return;

    final x = scene.scale?.xForIndex(index) ?? marks.first.center.dx;
    drawTrackball(
      canvas,
      x: x,
      top: bounds.top,
      bottom: bounds.bottom,
      lineColor: theme.crosshair,
    );
    for (final mark in marks) {
      _drawNeonDot(
        canvas,
        center: mark.center,
        color: mark.color,
        surface: theme.surface,
        radius: _activeDotRadius,
      );
    }
    final candleRows = candleTooltipRows?.call(index);
    final title = candleRows == null
        ? null
        : candleTooltipTitle?.call(index) ??
            (marks.first.label.isEmpty ? null : marks.first.label);
    _drawMarketTooltip(
      canvas,
      anchor: Offset(
        x,
        MarketLineChart.tooltipTopForMarks(
          [for (final mark in marks) mark.center.dy],
          rowCount: candleRows?.length ?? marks.length,
          hasTitle: title != null,
        ),
      ),
      container: size,
      title: title,
      background: theme.tooltipBackground,
      textColor: theme.tooltipText,
      mutedTextColor: theme.tooltipMutedText,
      rows: candleRows == null
          ? [
              for (final mark in marks)
                TooltipRow(rowLabel(mark), swatch: mark.color),
            ]
          : [for (final row in candleRows) TooltipRow(row)],
    );
  }

  @override
  bool shouldRepaint(covariant _MarketLineTooltipPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.theme != theme ||
      oldDelegate.rowLabel != rowLabel ||
      oldDelegate.candleTooltipTitle != candleTooltipTitle ||
      oldDelegate.candleTooltipRows != candleTooltipRows;
}

class _MarketLineChartScale extends CartesianScale {
  final Map<int, double> _xByIndex;

  _MarketLineChartScale({
    required super.bounds,
    required super.count,
    required super.minValue,
    required super.maxValue,
    required Map<int, double> xByIndex,
  }) : _xByIndex = Map.unmodifiable(xByIndex);

  @override
  double xForIndex(int index) => _xByIndex[index] ?? super.xForIndex(index);

  @override
  int nearestIndex(double px) {
    if (_xByIndex.isEmpty || !px.isFinite) return super.nearestIndex(px);

    var nearest = _xByIndex.keys.first;
    var nearestDistance = (_xByIndex[nearest]! - px).abs();
    for (final entry in _xByIndex.entries.skip(1)) {
      final distance = (entry.value - px).abs();
      if (distance < nearestDistance) {
        nearest = entry.key;
        nearestDistance = distance;
      }
    }
    return nearest;
  }
}

class _MarketLineChartRenderer extends ChartRenderer
    implements InteractiveRenderer {
  final List<MarketLineChartSeries> series;
  final List<MarketCandlePoint> candles;
  final bool loading;
  final bool showCandlesticks;
  final double minY;
  final double maxY;
  final bool curveLines;

  /// Replaces each series with its trailing average of up to 20 observations.
  final bool showRollingAverage;
  final double curveSmoothness;
  final bool showGridlines;
  final bool fillChartArea;
  final List<_LineChartAxisLabel> xLabels;
  final int? uniformXCount;
  final (double, double)? xAxisBounds;
  final int firstColumn;
  final Color axisLabelColor;
  final String Function(double value) yLabelFormatter;
  final double leftInset;
  final String _accessibilityLabel;
  final String? _accessibilityValue;

  const _MarketLineChartRenderer({
    required this.series,
    required this.candles,
    required this.loading,
    required this.showCandlesticks,
    required this.minY,
    required this.maxY,
    required this.curveLines,
    this.showRollingAverage = false,
    required this.curveSmoothness,
    required this.showGridlines,
    required this.fillChartArea,
    required this.xLabels,
    required this.uniformXCount,
    this.xAxisBounds,
    this.firstColumn = 0,
    required this.axisLabelColor,
    required this.yLabelFormatter,
    required this.leftInset,
    required String accessibilityLabel,
    required String? accessibilityValue,
  })  : _accessibilityLabel = accessibilityLabel,
        _accessibilityValue = accessibilityValue;

  List<Object> get dataSignature => [
        loading,
        uniformXCount ?? -1,
        showGridlines,
        fillChartArea,
        for (final candle in candles)
          (
            candle.column,
            candle.seriesIndex,
            candle.sampled,
            candle.open,
            candle.high,
            candle.low,
            candle.close,
          ),
        ...xLabels.map((label) => (label.x, label.column, label.text)),
        for (final line in series) ...[
          line.name,
          for (final point in line.points)
            (point.x, point.y, point.column, point.comparisonValue),
        ],
      ];

  _MarketLineChartRenderer zoomTo(int start, int end) {
    final visibleSeries = <MarketLineChartSeries>[];
    for (final line in series) {
      final points = [
        for (var i = 0; i < line.points.length; i++)
          if ((line.points[i].column ?? i) >= start &&
              (line.points[i].column ?? i) <= end)
            MarketLineChartPoint(
              line.points[i].x,
              line.points[i].y,
              column: line.points[i].column ?? i,
              comparisonValue: line.points[i].comparisonValue,
            ),
      ];
      final compare = points.any((point) => point.comparisonValue != null);
      final values = compare
          ? scalePortfolioSeriesForComparison(
              points.map((point) => point.comparisonValue ?? point.y),
            )
          : points.map((point) => point.y).toList();
      visibleSeries.add(
        MarketLineChartSeries(
          points: [
            for (var i = 0; i < points.length; i++)
              MarketLineChartPoint(
                points[i].x,
                values[i],
                column: points[i].column,
                comparisonValue: points[i].comparisonValue,
              ),
          ],
          color: line.color,
          name: line.name,
          fill: line.fill,
          strokeWidth: line.strokeWidth,
        ),
      );
    }
    final visibleCandles = <MarketCandlePoint>[];
    final seenSeries = <int>{};
    for (final candle in candles) {
      if (candle.column < start || candle.column > end) continue;
      final line = series[candle.seriesIndex];
      final selected = [
        for (var i = 0; i < line.points.length; i++)
          if ((line.points[i].column ?? i) >= start &&
              (line.points[i].column ?? i) <= end)
            line.points[i],
      ];
      if (selected.isEmpty) continue;
      final compare = selected.any((point) => point.comparisonValue != null);
      final firstY = selected.first.y;
      final divisor = 1 + firstY / 100;
      double rebase(double value) =>
          compare && divisor.abs() > 1e-9 ? (value - firstY) / divisor : value;
      final close = rebase(candle.close);
      final open = candle.sampled && seenSeries.add(candle.seriesIndex)
          ? close
          : rebase(candle.open);
      visibleCandles.add(
        MarketCandlePoint(
          column: candle.column,
          seriesIndex: candle.seriesIndex,
          sampled: candle.sampled,
          open: open,
          high: candle.sampled ? max(open, close) : rebase(candle.high),
          low: candle.sampled ? min(open, close) : rebase(candle.low),
          close: close,
        ),
      );
    }
    final bounds = _calculateYBounds([
      for (final line in visibleSeries) ...line.points,
      for (final candle in visibleCandles) ...[
        MarketLineChartPoint(candle.column.toDouble(), candle.high),
        MarketLineChartPoint(candle.column.toDouble(), candle.low),
      ],
    ]);
    return _MarketLineChartRenderer(
      series: visibleSeries,
      candles: visibleCandles,
      loading: loading,
      showCandlesticks: showCandlesticks,
      minY: bounds.$1,
      maxY: bounds.$2,
      curveLines: curveLines,
      showRollingAverage: showRollingAverage,
      curveSmoothness: curveSmoothness,
      showGridlines: showGridlines,
      fillChartArea: fillChartArea,
      xLabels: [
        for (final label in xLabels)
          if ((label.column ?? label.x) >= start &&
              (label.column ?? label.x) <= end)
            label,
      ],
      uniformXCount: uniformXCount == null ? null : end - start + 1,
      firstColumn: start,
      axisLabelColor: axisLabelColor,
      yLabelFormatter: yLabelFormatter,
      leftInset: leftInset,
      accessibilityLabel: _accessibilityLabel,
      accessibilityValue: null,
    );
  }

  ChartBounds _bounds(Size size) => ChartBounds.insets(
        size,
        left: leftInset,
        top: _chartTopInset,
        right: 32,
        bottom: _chartBottomLabelInset,
      );

  List<MarketLineChartPoint> get _allPoints => [
        for (final line in series) ...line.points,
      ];

  bool hasIndex(int index) {
    for (final line in series) {
      for (var pointIndex = 0; pointIndex < line.points.length; pointIndex++) {
        if ((line.points[pointIndex].column ?? pointIndex) == index)
          return true;
      }
    }
    return false;
  }

  (double, double) get _xBounds {
    if (xAxisBounds != null) return xAxisBounds!;
    final points = _allPoints;
    if (points.isEmpty) return (0, 1);
    final minX = points.map((point) => point.x).reduce(min);
    final maxX = points.map((point) => point.x).reduce(max);
    return maxX == minX ? (minX - 0.5, maxX + 0.5) : (minX, maxX);
  }

  double _xForPoint(
    MarketLineChartPoint point,
    int pointIndex,
    ChartBounds bounds,
  ) {
    final count = uniformXCount;
    if (count != null) {
      if (count <= 1) return bounds.left + bounds.width / 2;
      final column = point.column ?? pointIndex;
      return bounds.left + bounds.width * (column - firstColumn) / (count - 1);
    }

    final xBounds = _xBounds;
    return bounds.left +
        bounds.width * (point.x - xBounds.$1) / (xBounds.$2 - xBounds.$1);
  }

  double _yForValue(double value, ChartBounds bounds) {
    final span = maxY - minY;
    if (span == 0) return bounds.bottom;
    return bounds.bottom - (value - minY) / span * bounds.height;
  }

  List<Offset> _pixelPoints(MarketLineChartSeries line, ChartBounds bounds) => [
        for (var i = 0; i < line.points.length; i++)
          Offset(
            _xForPoint(line.points[i], i, bounds),
            _yForValue(line.points[i].y, bounds),
          ),
      ];

  Path _linePath(List<Offset> points) {
    if (!curveLines || points.length < 3) return polylinePath(points);

    final tension = curveSmoothness.clamp(0.0, 1.0);
    if ((tension - 0.35).abs() < 0.001) return smoothPath(points);

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    final controlScale = tension / 2.1;
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 >= points.length ? i + 1 : i + 2];
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) * controlScale,
        p1.dy + (p2.dy - p0.dy) * controlScale,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) * controlScale,
        p2.dy - (p3.dy - p1.dy) * controlScale,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawSeries(
    Canvas canvas,
    ChartBounds bounds,
    MarketLineChartSeries line, {
    required bool fill,
    required double progress,
  }) {
    final points = _pixelPoints(line, bounds);
    if (points.length < 2) return;

    final path = _linePath(points);
    final clamped = progress.clamp(0.0, 1.0);
    var drawn = path;
    if (clamped < 1) {
      drawn = Path();
      for (final metric in path.computeMetrics()) {
        drawn.addPath(
          metric.extractPath(0, metric.length * clamped),
          Offset.zero,
        );
      }
    }

    if (fill && fillChartArea) {
      final fillPath = Path.from(path)
        ..lineTo(points.last.dx, bounds.bottom)
        ..lineTo(points.first.dx, bounds.bottom)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = areaGradientShader(
            line.color,
            top: points.map((point) => point.dy).reduce(min),
            bottom: bounds.bottom,
            topAlpha: 0.3,
          ),
      );
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _drawAxes(Canvas canvas, ChartBounds bounds) {
    const tickCount = 4;
    for (var i = 0; i <= tickCount; i++) {
      final value = minY + (maxY - minY) * i / tickCount;
      final y = _yForValue(value, bounds);
      if (loading) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bounds.left - 41, y - 5, 34, 10),
            const Radius.circular(5),
          ),
          Paint()..color = axisLabelColor.withValues(alpha: 0.18),
        );
        continue;
      }
      drawChartText(
        canvas,
        yLabelFormatter(value),
        Offset(bounds.left - 7, y),
        color: axisLabelColor,
        fontSize: _axisLabelFontSize,
        h: HAlign.end,
        v: VAlign.center,
      );
    }

    if (xLabels.isEmpty) return;
    final centers = <double>[];
    final widths = <double>[];
    final candidates = MarketLineChart.xAxisLabelCandidates(
      xLabels.length,
      bounds.width,
    );
    for (final index in candidates) {
      final label = xLabels[index];
      final point = MarketLineChartPoint(label.x, 0, column: label.column);
      centers.add(_xForPoint(point, label.column ?? index, bounds));
      widths.add(
        measureChartText(
          label.text,
          fontSize: _axisLabelFontSize,
          color: axisLabelColor,
        ),
      );
    }
    final keep = MarketLineChart.selectXAxisLabelIndices(
      centers,
      widths,
      _xAxisLabelMinGap,
    );
    for (final i in keep) {
      drawChartText(
        canvas,
        xLabels[candidates[i]].text,
        Offset(centers[i], bounds.bottom + 15),
        color: axisLabelColor,
        fontSize: _axisLabelFontSize,
        h: HAlign.center,
        v: VAlign.center,
      );
    }
  }

  List<MarketLineChartSeries> get _displaySeries {
    if (!showRollingAverage) return series;
    return series.map((line) {
      var total = 0.0;
      final points = <MarketLineChartPoint>[];
      for (var index = 0; index < line.points.length; index++) {
        final point = line.points[index];
        total += point.y;
        if (index >= 20) total -= line.points[index - 20].y;
        points.add(
          MarketLineChartPoint(
            point.x,
            total / min(index + 1, 20),
            column: point.column,
            comparisonValue: point.comparisonValue,
          ),
        );
      }
      return MarketLineChartSeries(
        points: points,
        color: line.color,
        name: line.name,
        fill: line.fill,
        strokeWidth: line.strokeWidth,
      );
    }).toList();
  }

  @override
  void draw(
    Canvas canvas,
    Size size,
    DrafterThemeColors theme,
    double progress,
  ) {
    if (size.isEmpty) return;
    final bounds = _bounds(size);
    if (showGridlines) {
      final gridPaint = Paint()
        ..color = axisLabelColor.withValues(alpha: 0.12)
        ..strokeWidth = 1;
      for (var i = 0; i <= 4; i++) {
        final y = bounds.top + bounds.height * i / 4;
        canvas.drawLine(
          Offset(bounds.left, y),
          Offset(bounds.right, y),
          gridPaint,
        );
      }
    }
    _drawAxes(canvas, bounds);

    final displayedSeries = _displaySeries;
    if (showCandlesticks && candles.isNotEmpty) {
      _drawCandles(canvas, bounds);
      if (showRollingAverage) {
        for (final line in displayedSeries) {
          _drawSeries(canvas, bounds, line, fill: false, progress: progress);
        }
      }
    } else {
      for (final line in displayedSeries) {
        _drawSeries(
          canvas,
          bounds,
          line,
          fill: line.fill,
          progress: progress,
        );
      }
    }
  }

  void _drawCandles(Canvas canvas, ChartBounds bounds) {
    if (candles.isEmpty) return;
    final seriesCount = series.length;
    var spacing = uniformXCount == null || uniformXCount! < 2
        ? bounds.width
        : bounds.width / (uniformXCount! - 1);
    if (uniformXCount == null) {
      for (final line in series) {
        if (line.points.length < 2) continue;
        final first = _xForPoint(line.points.first, 0, bounds);
        final last =
            _xForPoint(line.points.last, line.points.length - 1, bounds);
        spacing = min(spacing, (last - first).abs() / (line.points.length - 1));
      }
    }
    final groupSize = max(
      1,
      (3.5 * max(1, seriesCount) / max(spacing, 0.01)).ceil(),
    );
    final groupedSpacing = spacing * groupSize;
    final barWidth =
        (groupedSpacing * 0.65 / max(1, seriesCount)).clamp(1.5, 8.0);
    for (var seriesIndex = 0; seriesIndex < seriesCount; seriesIndex++) {
      final source = [
        for (final candle in candles)
          if (candle.seriesIndex == seriesIndex) candle,
      ];
      final linePoints = series[seriesIndex].points;
      final xByColumn = <int, double>{
        for (var i = 0; i < linePoints.length; i++)
          (linePoints[i].column ?? i): linePoints[i].x,
      };
      final seriesColor = series[seriesIndex].color;
      for (var start = 0; start < source.length; start += groupSize) {
        final group = source.skip(start).take(groupSize).toList();
        final first = group.first;
        final last = group.last;
        final high = group.map((candle) => candle.high).reduce(max);
        final low = group.map((candle) => candle.low).reduce(min);
        final startX = _xForPoint(
          MarketLineChartPoint(
            xByColumn[first.column] ?? first.column.toDouble(),
            first.close,
            column: first.column,
          ),
          first.column,
          bounds,
        );
        final endX = _xForPoint(
          MarketLineChartPoint(
            xByColumn[last.column] ?? last.column.toDouble(),
            last.close,
            column: last.column,
          ),
          last.column,
          bounds,
        );
        final x = (startX + endX) / 2 +
            (seriesIndex - (seriesCount - 1) / 2) * barWidth;
        final positive = last.close >= first.open;
        final color = switch (true) {
          _ when (seriesCount == 1) && (positive) => const Color(0xFF26A69A),
          _ when (seriesCount == 1) => const Color(0xFFEF5350),
          _ => seriesColor,
        };
        final highY = _yForValue(high, bounds);
        final lowY = _yForValue(low, bounds);
        final openY = _yForValue(first.open, bounds);
        final closeY = _yForValue(last.close, bounds);
        if (!group.every((candle) => candle.sampled)) {
          canvas.drawLine(
            Offset(x, highY),
            Offset(x, lowY),
            Paint()
              ..color = color
              ..strokeWidth = 1.2,
          );
        }
        final bodyTop = min(openY, closeY);
        final bodyBottom = max(openY, closeY);
        final body = Rect.fromLTWH(
          x - barWidth / 2,
          bodyTop,
          barWidth,
          max(bodyBottom - bodyTop, 1.2),
        );
        canvas.drawRect(
          body,
          Paint()
            ..color = positive && seriesCount > 1
                ? color.withValues(alpha: 0.25)
                : color,
        );
        if (seriesCount > 1) {
          canvas.drawRect(
            body,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
    }
  }

  @override
  ChartScene buildScene(Size size) {
    final bounds = _bounds(size);
    final displayedSeries = _displaySeries;
    final xByIndex = <int, double>{};

    for (final line in displayedSeries) {
      for (var pointIndex = 0; pointIndex < line.points.length; pointIndex++) {
        final point = line.points[pointIndex];
        final index = point.column ?? pointIndex;
        xByIndex.putIfAbsent(
          index,
          () => _xForPoint(point, pointIndex, bounds),
        );
      }
    }

    final orderedColumns = xByIndex.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final hitRegions = <int, Rect>{};
    for (var i = 0; i < orderedColumns.length; i++) {
      final column = orderedColumns[i];
      final left = i == 0
          ? bounds.left
          : (orderedColumns[i - 1].value + column.value) / 2;
      final right = i == orderedColumns.length - 1
          ? bounds.right
          : (column.value + orderedColumns[i + 1].value) / 2;
      hitRegions[column.key] = Rect.fromLTRB(
        left,
        bounds.top,
        right,
        bounds.bottom,
      );
    }

    final marks = <PlotMark>[];
    for (var seriesIndex = 0;
        seriesIndex < displayedSeries.length;
        seriesIndex++) {
      final line = displayedSeries[seriesIndex];
      for (var pointIndex = 0; pointIndex < line.points.length; pointIndex++) {
        final point = line.points[pointIndex];
        final index = point.column ?? pointIndex;
        marks.add(
          PlotMark(
            index: index,
            seriesIndex: seriesIndex,
            seriesName: line.name,
            label: '',
            value: point.y,
            center: Offset(
              _xForPoint(point, pointIndex, bounds),
              _yForValue(point.y, bounds),
            ),
            region: hitRegions[index],
            color: line.color,
          ),
        );
      }
    }

    final scale = xByIndex.isEmpty
        ? null
        : _MarketLineChartScale(
            bounds: bounds,
            count: xByIndex.length,
            minValue: minY,
            maxValue: maxY,
            xByIndex: xByIndex,
          );

    return ChartScene(
      bounds: bounds,
      scale: scale,
      categories: const [],
      marks: marks,
    );
  }

  @override
  String get accessibilityLabel => _accessibilityLabel;

  @override
  String get accessibilityValue =>
      _accessibilityValue ??
      (_allPoints.isEmpty ? 'No data' : '${_allPoints.length} points');
}
