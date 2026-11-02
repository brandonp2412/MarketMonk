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
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 1;
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
    canvas.scale(size.width / 112, size.height / 72);
    const trend = [
      Offset(12, 51),
      Offset(28, 40),
      Offset(43, 46),
      Offset(58, 25),
      Offset(73, 33),
      Offset(98, 16),
    ];
    final path = Path()..moveTo(trend.first.dx, trend.first.dy);
    for (final point in trend.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..color = colors.primary.withValues(alpha: 0.12);
    canvas.drawPath(path, paint);
    final metric = path.computeMetrics().first;
    final distance = metric.length * animation.value;
    paint.color = colors.primary;
    canvas.drawPath(metric.extractPath(0, distance), paint);
    final head = metric.getTangentForOffset(distance)?.position ?? trend.first;
    paint
      ..style = PaintingStyle.fill
      ..color = colors.primary.withValues(alpha: 0.12);
    canvas.drawCircle(head, 7, paint);
    paint.color = colors.primary;
    canvas.drawCircle(head, 3, paint);
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
