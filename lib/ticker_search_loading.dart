import 'dart:math' as math;

import 'package:flutter/material.dart';

class TickerSearchLoading extends StatefulWidget {
  const TickerSearchLoading({super.key});

  @override
  State<TickerSearchLoading> createState() => _TickerSearchLoadingState();
}

class _TickerSearchLoadingState extends State<TickerSearchLoading>
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
      _animation.value = 0.5;
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
      label: MaterialLocalizations.of(context).searchFieldLabel,
      liveRegion: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: 88,
          height: 56,
          child: CustomPaint(
            painter: _SearchLoadingPainter(
              _animation,
              Theme.of(context).colorScheme,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchLoadingPainter extends CustomPainter {
  _SearchLoadingPainter(this.animation, this.colors)
      : super(repaint: animation);

  final Animation<double> animation;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 88, size.height / 56);
    final lens = Offset(44 + 16 * math.sin(animation.value * 2 * math.pi), 24);
    final paint = Paint()
      ..color = colors.primary.withValues(alpha: 0.18)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const heights = [10.0, 20.0, 14.0, 26.0, 19.0, 30.0];
    for (var i = 0; i < heights.length; i++) {
      final x = 17.0 + i * 10;
      canvas.drawLine(Offset(x, 40), Offset(x, 40 - heights[i]), paint);
    }
    paint.color = colors.surface.withValues(alpha: 0.85);
    canvas.drawCircle(lens, 13, paint);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: lens, radius: 12)));
    paint.color = colors.primary;
    for (var i = 0; i < heights.length; i++) {
      final x = 17.0 + i * 10;
      canvas.drawLine(Offset(x, 40), Offset(x, 40 - heights[i]), paint);
    }
    canvas.restore();
    paint
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(lens, 14, paint);
    canvas.drawLine(
      lens + const Offset(10, 10),
      lens + const Offset(20, 20),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SearchLoadingPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.animation != animation;
}
