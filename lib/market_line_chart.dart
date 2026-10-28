import 'dart:async';
import 'dart:math';

import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:market_monk/portfolio_chart_scale.dart';

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

void _drawNeonDot(
  Canvas canvas, {
  required Offset center,
  required Color color,
  required Color surface,
  required double radius,
}) {
  final dark = surface.computeLuminance() < 0.5;
  final glowRadius = radius * 1.8;
  final highlight = Color.lerp(color, Colors.white, dark ? 0.65 : 0.4)!;
  canvas.drawCircle(
    center,
    glowRadius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: dark ? 0.4 : 0.24),
          color.withValues(alpha: 0.12),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
  );
  canvas.drawCircle(center, radius, Paint()..color = surface);
  canvas.drawCircle(
    center,
    radius - 0.75,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [highlight, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
  canvas.drawCircle(
    center,
    radius * 0.48,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [highlight, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.48)),
  );
}

void _drawMarketTooltip(
  Canvas canvas, {
  required Offset anchor,
  required Size container,
  required List<TooltipRow> rows,
  required Color background,
  required Color textColor,
  required Color mutedTextColor,
  String? title,
}) {
  final hasTitle = title != null && title.isNotEmpty;
  if (rows.isEmpty && !hasTitle) return;

  var maxWidth = 0.0;
  if (hasTitle) {
    maxWidth = measureChartText(
      title,
      color: textColor,
      fontSize: _tooltipFontSize,
    );
  }
  for (final row in rows) {
    final textWidth = measureChartText(
      row.text,
      color: textColor,
      fontSize: _tooltipFontSize,
    );
    final rowWidth = textWidth +
        (row.swatch == null ? 0 : _tooltipSwatchSize + _tooltipSwatchGap);
    maxWidth = max(maxWidth, rowWidth);
  }

  final titleHeight = hasTitle ? _tooltipRowHeight : 0.0;
  final boxWidth = maxWidth + _tooltipPadding * 2;
  final boxHeight =
      titleHeight + rows.length * _tooltipRowHeight + _tooltipPadding * 2;
  var left = anchor.dx + 12;
  if (left + boxWidth > container.width) {
    left = anchor.dx - 12 - boxWidth;
  }
  left = left.clamp(0.0, max(0.0, container.width - boxWidth)).toDouble();
  final top =
      anchor.dy.clamp(0.0, max(0.0, container.height - boxHeight)).toDouble();

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxWidth, boxHeight),
      const Radius.circular(8),
    ),
    Paint()..color = background,
  );

  var rowTop = top + _tooltipPadding;
  if (hasTitle) {
    drawChartText(
      canvas,
      title,
      Offset(left + _tooltipPadding, rowTop + _tooltipRowHeight / 2),
      color: mutedTextColor,
      fontSize: _tooltipFontSize,
      v: VAlign.center,
    );
    rowTop += _tooltipRowHeight;
  }
  for (final row in rows) {
    final rowCenter = rowTop + _tooltipRowHeight / 2;
    var textX = left + _tooltipPadding;
    if (row.swatch case final color?) {
      _drawNeonDot(
        canvas,
        center: Offset(textX + _tooltipSwatchSize / 2, rowCenter),
        color: color,
        surface: background,
        radius: _tooltipSwatchSize / 2,
      );
      textX += _tooltipSwatchSize + _tooltipSwatchGap;
    }
    drawChartText(
      canvas,
      row.text,
      Offset(textX, rowCenter),
      color: textColor,
      fontSize: _tooltipFontSize,
      v: VAlign.center,
    );
    rowTop += _tooltipRowHeight;
  }
}

(double, double) _calculateYBounds(List<MarketLineChartPoint> points) {
  if (points.isEmpty) return (0, 1);

  var minY = points.map((point) => point.y).reduce(min);
  var maxY = points.map((point) => point.y).reduce(max);
  if (maxY - minY < 1.0) {
    final center = (maxY + minY) / 2;
    minY = center - 0.5;
    maxY = center + 0.5;
  }

  final padding = (maxY - minY) * _lineChartEdgePaddingFraction;
  return (minY - padding, maxY + padding);
}

class MarketLineChart extends StatelessWidget {
  final List<MarketLineChartSeries> series;
  final List<String> xLabels;
  final int pointCount;
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
  final double leftInset;
  final String accessibilityLabel;
  final String? accessibilityValue;

  /// Selected inclusive columns, retained by the caller across data changes.
  final (int, int)? range;

  /// Updates the caller-owned [range]; null restores the full period.
  final ValueChanged<(int, int)?>? onRangeChanged;

  const MarketLineChart({
    super.key,
    required this.series,
    required this.xLabels,
    required this.pointCount,
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
    this.leftInset = 64,
    this.accessibilityLabel = 'Price chart',
    this.accessibilityValue,
    this.range,
    this.onRangeChanged,
  });

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
        showCandlesticks: showCandlesticks,
        minY: yBounds.$1,
        maxY: yBounds.$2,
        curveLines: curveLines,
        showRollingAverage: showRollingAverage,
        curveSmoothness: curveSmoothness,
        xLabels: [
          for (var i = 0; i < xLabels.length; i++)
            _LineChartAxisLabel(i.toDouble(), xLabels[i], column: i),
        ],
        uniformXCount: pointCount,
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
    );
  }
}

class _MarketLineChartInteraction extends StatefulWidget {
  final _MarketLineChartRenderer renderer;
  final String Function(PlotMark mark) rowLabel;
  final String Function(int index)? candleTooltipTitle;
  final List<String> Function(int index)? candleTooltipRows;
  final bool stickyTooltip;
  final ValueNotifier<int?>? externalSelection;
  final (int, int)? range;
  final ValueChanged<(int, int)?>? onRangeChanged;
  const _MarketLineChartInteraction({
    required this.renderer,
    required this.rowLabel,
    this.candleTooltipTitle,
    this.candleTooltipRows,
    this.stickyTooltip = false,
    this.externalSelection,
    this.range,
    this.onRangeChanged,
  });

  @override
  State<_MarketLineChartInteraction> createState() =>
      _MarketLineChartInteractionState();
}

class _MarketLineChartInteractionState
    extends State<_MarketLineChartInteraction> {
  final ValueNotifier<int?> _ownedSelection = ValueNotifier(null);
  ValueNotifier<int?> get _activeIndex =>
      widget.externalSelection ?? _ownedSelection;

  (int, int)? _zoom;
  Offset? _dragStart;
  double? _dragX;
  int? _dragPointer;
  bool _scrubFrameScheduled = false;
  int? _pendingScrubIndex;

  (int, int)? get _range => widget.range ?? _zoom;

  _MarketLineChartRenderer get _renderer => _range == null
      ? widget.renderer
      : widget.renderer.zoomTo(_range!.$1, _range!.$2);

  void _setRange((int, int)? range) {
    setState(() {
      _zoom = widget.onRangeChanged == null ? range : null;
      _clear();
    });
    widget.onRangeChanged?.call(range);
  }

  Future<void> _showStartDateMenu(
    Offset globalPosition,
    int start,
    int end,
  ) async {
    final dataSignature = widget.renderer.dataSignature;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          enabled: start < end,
          child: const Text('Start from this date'),
        ),
      ],
    );
    if (!mounted ||
        selected != true ||
        !listEquals(dataSignature, widget.renderer.dataSignature)) return;
    _setRange((start, end));
    setState(() {
      _dragStart = null;
      _dragX = null;
      _dragPointer = null;
      _clear();
    });
  }

  void _activate(Offset position, ChartScene scene) {
    _activeIndex.value = ChartHitTest.nearestIndexAtX(scene, position.dx);
  }

  void _activateScrub(Offset position, ChartScene scene) {
    final index = ChartHitTest.nearestIndexAtX(scene, position.dx);
    if (index == null) {
      _clear();
      return;
    }
    if (ChartHitTest.marksAtIndex(scene, index).length <= 1) {
      _pendingScrubIndex = null;
      _activeIndex.value = index;
      return;
    }
    _pendingScrubIndex = index;
    if (_scrubFrameScheduled) return;
    _scrubFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scrubFrameScheduled = false;
      final pending = _pendingScrubIndex;
      _pendingScrubIndex = null;
      if (mounted && pending != null) _activeIndex.value = pending;
    });
  }

  void _clear() {
    _pendingScrubIndex = null;
    _activeIndex.value = null;
  }

  bool get _keepTooltipOnTapUp {
    if (widget.stickyTooltip) return true;
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      _ => false,
    };
  }

  @override
  void didUpdateWidget(_MarketLineChartInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
      oldWidget.renderer.dataSignature,
      widget.renderer.dataSignature,
    )) {
      _zoom = null;
      _dragStart = null;
      _dragX = null;
      _dragPointer = null;
      _clear();
    }
    if (oldWidget.stickyTooltip != widget.stickyTooltip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clear();
      });
    }
    final index = _activeIndex.value;
    if (index != null && !_renderer.hasIndex(index)) _clear();
  }

  @override
  void dispose() {
    _pendingScrubIndex = null;
    _ownedSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = dark ? DrafterThemeColors.dark : DrafterThemeColors.light;

    return ValueListenableBuilder<int?>(
      valueListenable: _activeIndex,
      builder: (context, activeIndex, chart) => PopScope(
        canPop: widget.externalSelection != null ||
            !widget.stickyTooltip ||
            activeIndex == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.externalSelection == null) _clear();
        },
        child: chart!,
      ),
      child: TapRegion(
        onTapOutside: (_) {
          if (widget.stickyTooltip) _clear();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final renderer = _renderer;
            final scene = renderer.buildScene(size);

            return MouseRegion(
              onHover: (event) => _activate(event.localPosition, scene),
              onExit: (_) {
                if (_dragPointer == null) _clear();
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _activate(event.localPosition, scene);
                  final bounds = scene.bounds;
                  if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kPrimaryMouseButton &&
                      bounds != null &&
                      Rect.fromLTRB(
                        bounds.left,
                        bounds.top,
                        bounds.right,
                        bounds.bottom,
                      ).contains(event.localPosition)) {
                    _dragStart = event.localPosition;
                    _dragPointer = event.pointer;
                  }
                },
                onPointerMove: (event) {
                  if (event.pointer != _dragPointer || _dragStart == null)
                    return;
                  setState(() {
                    _dragX = event.localPosition.dx;
                  });
                  _activate(event.localPosition, scene);
                },
                onPointerUp: (event) {
                  if (event.pointer == _dragPointer) {
                    final start = _dragStart;
                    if (start != null &&
                        (event.localPosition.dx - start.dx).abs() >= 8) {
                      final first =
                          ChartHitTest.nearestIndexAtX(scene, start.dx);
                      final last = ChartHitTest.nearestIndexAtX(
                        scene,
                        event.localPosition.dx,
                      );
                      if (first != null && last != null && first != last) {
                        _setRange((min(first, last), max(first, last)));
                      }
                    }
                    setState(() {
                      _dragStart = null;
                      _dragX = null;
                      _dragPointer = null;
                      _clear();
                    });
                  } else {
                    _activate(event.localPosition, scene);
                  }
                  if (!_keepTooltipOnTapUp) _clear();
                },
                onPointerCancel: (_) => setState(() {
                  _dragStart = null;
                  _dragX = null;
                  _dragPointer = null;
                  _clear();
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapUp: (details) {
                    final bounds = scene.bounds;
                    if (bounds == null ||
                        !Rect.fromLTRB(
                          bounds.left,
                          bounds.top,
                          bounds.right,
                          bounds.bottom,
                        ).contains(details.localPosition)) return;
                    final start = ChartHitTest.nearestIndexAtX(
                      scene,
                      details.localPosition.dx,
                    );
                    if (start == null || scene.marks.isEmpty) return;
                    final end =
                        scene.marks.map((mark) => mark.index).reduce(max);
                    unawaited(
                      _showStartDateMenu(details.globalPosition, start, end),
                    );
                  },
                  onLongPressStart: (details) =>
                      _activate(details.localPosition, scene),
                  onLongPressMoveUpdate: (details) =>
                      _activateScrub(details.localPosition, scene),
                  onLongPressEnd: (_) {
                    if (_dragPointer == null && !widget.stickyTooltip) _clear();
                  },
                  onLongPressCancel: () {
                    if (_dragPointer == null && !widget.stickyTooltip) _clear();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DrafterTheme(
                        colors: theme,
                        child: ChartCanvas(
                          renderer: renderer,
                          animate: false,
                        ),
                      ),
                      if (_dragStart != null &&
                          _dragX != null &&
                          scene.bounds != null)
                        Positioned(
                          left: min(_dragStart!.dx, _dragX!)
                              .clamp(scene.bounds!.left, scene.bounds!.right),
                          top: scene.bounds!.top,
                          width: (max(_dragStart!.dx, _dragX!).clamp(
                                scene.bounds!.left,
                                scene.bounds!.right,
                              ) -
                              min(_dragStart!.dx, _dragX!).clamp(
                                scene.bounds!.left,
                                scene.bounds!.right,
                              )),
                          height: scene.bounds!.height,
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                      if (_range != null)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            tooltip: 'Reset zoom',
                            icon: const Icon(Icons.zoom_out),
                            onPressed: () => _setRange(null),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _MarketLineTooltipPainter(
                                activeIndex: _activeIndex,
                                scene: scene,
                                theme: theme,
                                rowLabel: widget.rowLabel,
                                candleTooltipTitle: widget.candleTooltipTitle,
                                candleTooltipRows: widget.candleTooltipRows,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

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
  final bool showCandlesticks;
  final double minY;
  final double maxY;
  final bool curveLines;

  /// Replaces each series with its trailing average of up to 20 observations.
  final bool showRollingAverage;
  final double curveSmoothness;
  final List<_LineChartAxisLabel> xLabels;
  final int? uniformXCount;
  final int firstColumn;
  final Color axisLabelColor;
  final String Function(double value) yLabelFormatter;
  final double leftInset;
  final String _accessibilityLabel;
  final String? _accessibilityValue;

  const _MarketLineChartRenderer({
    required this.series,
    required this.candles,
    required this.showCandlesticks,
    required this.minY,
    required this.maxY,
    required this.curveLines,
    this.showRollingAverage = false,
    required this.curveSmoothness,
    required this.xLabels,
    required this.uniformXCount,
    this.firstColumn = 0,
    required this.axisLabelColor,
    required this.yLabelFormatter,
    required this.leftInset,
    required String accessibilityLabel,
    required String? accessibilityValue,
  })  : _accessibilityLabel = accessibilityLabel,
        _accessibilityValue = accessibilityValue;

  List<Object> get dataSignature => [
        uniformXCount ?? -1,
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
      showCandlesticks: showCandlesticks,
      minY: bounds.$1,
      maxY: bounds.$2,
      curveLines: curveLines,
      showRollingAverage: showRollingAverage,
      curveSmoothness: curveSmoothness,
      xLabels: [
        for (final label in xLabels)
          if ((label.column ?? label.x) >= start &&
              (label.column ?? label.x) <= end)
            label,
      ],
      uniformXCount: end - start + 1,
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
    final metrics = path.computeMetrics().toList();
    final drawn = Path();
    final clamped = progress.clamp(0.0, 1.0);
    for (final metric in metrics) {
      drawn.addPath(
        metric.extractPath(0, metric.length * clamped),
        Offset.zero,
      );
    }

    if (fill) {
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
    for (final label in xLabels) {
      final point = MarketLineChartPoint(label.x, 0, column: label.column);
      centers.add(_xForPoint(point, label.column ?? centers.length, bounds));
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
    ).toSet();
    for (var i = 0; i < xLabels.length; i++) {
      if (!keep.contains(i)) continue;
      drawChartText(
        canvas,
        xLabels[i].text,
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
    final spacing = uniformXCount == null || uniformXCount! < 2
        ? bounds.width
        : bounds.width / (uniformXCount! - 1);
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
      final seriesColor = series[seriesIndex].color;
      for (var start = 0; start < source.length; start += groupSize) {
        final group = source.skip(start).take(groupSize).toList();
        final first = group.first;
        final last = group.last;
        final high = group.map((candle) => candle.high).reduce(max);
        final low = group.map((candle) => candle.low).reduce(min);
        final startX = _xForPoint(
          MarketLineChartPoint(
            first.column.toDouble(),
            first.close,
            column: first.column,
          ),
          first.column,
          bounds,
        );
        final endX = _xForPoint(
          MarketLineChartPoint(
            last.column.toDouble(),
            last.close,
            column: last.column,
          ),
          last.column,
          bounds,
        );
        final x = (startX + endX) / 2 +
            (seriesIndex - (seriesCount - 1) / 2) * barWidth;
        final positive = last.close >= first.open;
        final color = seriesCount == 1
            ? (positive ? const Color(0xFF26A69A) : const Color(0xFFEF5350))
            : seriesColor;
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
