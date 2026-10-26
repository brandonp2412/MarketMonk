import 'dart:math';

import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
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

class TickerCandlestick extends StatefulWidget {
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
  State<TickerCandlestick> createState() => _TickerCandlestickState();
}

class _TickerCandlestickState extends State<TickerCandlestick> {
  final _activeIndex = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _activeIndex.dispose();
    super.dispose();
  }

  void _select(Offset position, ChartScene scene) {
    final index = ChartHitTest.nearestIndexAtX(scene, position.dx);
    if (_activeIndex.value != index) _activeIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chartTheme = DrafterThemeColors(
      palette: DrafterColors.palette,
      grid: colorScheme.onSurface.withValues(alpha: 0.07),
      label: colorScheme.onSurface.withValues(alpha: 0.62),
      surface: colorScheme.surface,
      isDark: dark,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final plotted = aggregatePriceCandles(
          widget.candles,
          max(1, (constraints.maxWidth / 8).floor()),
        );
        if (plotted.isEmpty) {
          return const Center(child: Text('No OHLC prices available'));
        }

        final dateFormat = DateFormat(
          widget.intraday
              ? 'HH:mm'
              : widget.candles.length > 400
                  ? 'MMM yy'
                  : 'd/M',
        );
        final displayRate =
            exchangeRate / requireUsdRate(widget.nativeCurrency);
        final rows = [
          for (final candle in plotted)
            Candle(
              label: dateFormat.format(candle.date),
              open: candle.open * displayRate,
              high: candle.high * displayRate,
              low: candle.low * displayRate,
              close: candle.close * displayRate,
            ),
        ];
        final renderer = CandlestickChartRenderer(
          candles: rows,
          movingAverages: [
            if (widget.showRollingAverage)
              MovingAverage(period: 20, color: colorScheme.primary),
          ],
        );
        final scene = renderer.buildScene(constraints.biggest);

        return DrafterTheme(
          colors: chartTheme,
          child: MouseRegion(
            onHover: (event) => _select(event.localPosition, scene),
            onExit: (_) => _activeIndex.value = null,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _select(event.localPosition, scene),
              onPointerMove: (event) => _select(event.localPosition, scene),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (details) =>
                    _select(details.localPosition, scene),
                onLongPressMoveUpdate: (details) =>
                    _select(details.localPosition, scene),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ChartCanvas(renderer: renderer, animate: false),
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _CandleCrosshairPainter(
                            scene: scene,
                            activeIndex: _activeIndex,
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.32),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int?>(
                      valueListenable: _activeIndex,
                      builder: (context, index, _) {
                        if (index == null || index >= plotted.length) {
                          return const SizedBox.shrink();
                        }
                        final candle = plotted[index];
                        final date = DateFormat(
                          widget.intraday ? 'd MMM HH:mm' : 'd MMM yyyy',
                        ).format(candle.date);
                        return Positioned(
                          top: 4,
                          left: index > plotted.length ~/ 2 ? 8 : null,
                          right: index <= plotted.length ~/ 2 ? 8 : null,
                          child: IgnorePointer(
                            child: Container(
                              key: const Key('candle-price-tooltip'),
                              constraints: const BoxConstraints(maxWidth: 236),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  _valuesRow(candle, colorScheme),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _valuesRow(PriceCandle candle, ColorScheme scheme) {
    Widget value(String label, double price) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: fmtNativeCurrency(price, widget.nativeCurrency),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
          ),
        );

    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        value('O', candle.open),
        value('H', candle.high),
        value('L', candle.low),
        value('C', candle.close),
      ],
    );
  }
}

class _CandleCrosshairPainter extends CustomPainter {
  final ChartScene scene;
  final ValueNotifier<int?> activeIndex;
  final Color color;

  _CandleCrosshairPainter({
    required this.scene,
    required this.activeIndex,
    required this.color,
  }) : super(repaint: activeIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final index = activeIndex.value;
    final bounds = scene.bounds;
    if (index == null || bounds == null || index >= scene.marks.length) return;
    final mark = scene.marks[index];
    final x = mark.center.dx;
    canvas.drawLine(
      Offset(x, bounds.top),
      Offset(x, bounds.bottom),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      mark.center,
      4.5,
      Paint()..color = mark.color,
    );
  }

  @override
  bool shouldRepaint(covariant _CandleCrosshairPainter old) =>
      old.scene != scene || old.color != color;
}
