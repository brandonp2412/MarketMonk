import 'dart:math' as math;

import 'package:flutter/material.dart';

class MarketChartLoading extends StatefulWidget {
  const MarketChartLoading({super.key});

  @override
  State<MarketChartLoading> createState() => _MarketChartLoadingState();
}

class _MarketChartLoadingState extends State<MarketChartLoading>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 0;
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      liveRegion: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: 88,
          height: 56,
          child: CustomPaint(
            painter: _ChartLoadingPainter(
              _animation,
              Theme.of(context).colorScheme,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartLoadingPainter extends CustomPainter {
  _ChartLoadingPainter(this.animation, this.colors) : super(repaint: animation);

  final Animation<double> animation;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 88, size.height / 56);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;
    for (final y in [16.0, 32.0, 48.0]) {
      paint.color = colors.primary.withValues(alpha: 0.08);
      canvas.drawLine(Offset(5, y), Offset(83, y), paint);
    }
    final points = <Offset>[];
    for (var i = 0; i < 5; i++) {
      final wave = (math.sin(animation.value * math.pi * 2 - i * 0.7) + 1) / 2;
      final x = 12.0 + i * 16;
      final y = 35.0 - i * 4 - wave * 8;
      points.add(Offset(x, y));
      paint
        ..color = colors.primary.withValues(alpha: 0.45 + wave * 0.55)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(x, y - 10), Offset(x, y + 10), paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: 7,
            height: 10 + wave * 5,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    paint
      ..color = colors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, paint);
    paint
      ..style = PaintingStyle.fill
      ..color = colors.primary.withValues(alpha: 0.12);
    canvas.drawCircle(points.last, 7, paint);
    paint.color = colors.primary;
    canvas.drawCircle(points.last, 3, paint);
  }

  @override
  bool shouldRepaint(_ChartLoadingPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.animation != animation;
}

class MarketChartRefreshIndicator extends StatefulWidget {
  const MarketChartRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  State<MarketChartRefreshIndicator> createState() =>
      _MarketChartRefreshIndicatorState();
}

class _MarketChartRefreshIndicatorState
    extends State<MarketChartRefreshIndicator> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          triggerMode: RefreshIndicatorTriggerMode.anywhere,
          onRefresh: widget.onRefresh,
          onStatusChange: (status) => setState(() => _status = status),
          child: widget.child,
        ),
        if (_status != null &&
            _status != RefreshIndicatorStatus.canceled &&
            _status != RefreshIndicatorStatus.done)
          Positioned(
            top: widget.edgeOffset + 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(20),
                  child: const MarketChartLoading(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
