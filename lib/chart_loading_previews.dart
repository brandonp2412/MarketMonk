import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChartLoadingPreviews extends StatefulWidget {
  const ChartLoadingPreviews({super.key});

  @override
  State<ChartLoadingPreviews> createState() => _ChartLoadingPreviewsState();
}

class _ChartLoadingPreviewsState extends State<ChartLoadingPreviews>
    with SingleTickerProviderStateMixin {
  static const _names = [
    'Bouncing candles',
    'Drawing the trend',
    'Market heartbeat',
    'Rising bars',
    'Orbiting candles',
    'Zen ripple',
    'Chart surfer',
    'Bull steps',
    'Scanning the market',
    'Monk breath',
  ];
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
    value: 0.25,
  );
  int _selected = 0;
  bool _playing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _playing = false;
    }
  }

  void _select(int index) {
    setState(() {
      _selected = index;
      _playing = !MediaQuery.disableAnimationsOf(context);
      if (_playing) {
        _animation.repeat();
      }
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Loading indicator lab', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tap a design to preview it. Tell me your favourite number.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              height: 128,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: ValueKey('loading-preview-$_selected'),
                    size: const Size(112, 72),
                    painter: _PreviewPainter(
                      _animation,
                      theme.colorScheme,
                      _selected,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected + 1}. ${_names[_selected]}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: _playing ? 'Pause preview' : 'Play preview',
                  onPressed: MediaQuery.disableAnimationsOf(context)
                      ? null
                      : () => setState(() {
                            _playing = !_playing;
                            if (_playing) {
                              _animation.repeat();
                            } else {
                              _animation.stop();
                            }
                          }),
                  icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _names.length; i++)
                  ChoiceChip(
                    label: Text('${i + 1}. ${_names[i]}'),
                    selected: _selected == i,
                    onSelected: (_) => _select(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.animation, this.colors, this.design)
      : super(repaint: animation);

  final Animation<double> animation;
  final ColorScheme colors;
  final int design;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 112, size.height / 72);
    final t = animation.value;
    final cycle = t * math.pi * 2;
    final ink = Paint()
      ..color = colors.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(List<Offset> points, {double opacity = 1}) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      ink
        ..style = PaintingStyle.stroke
        ..color = colors.primary.withValues(alpha: opacity);
      canvas.drawPath(path, ink);
      ink.style = PaintingStyle.fill;
    }

    void dot(Offset point, double radius, double opacity) {
      ink.color = colors.primary.withValues(alpha: opacity);
      canvas.drawCircle(point, radius, ink);
    }

    void candle(double x, double y, double height, double opacity) {
      ink.color = colors.primary.withValues(alpha: opacity);
      canvas.drawLine(
        Offset(x, y - height / 2 - 5),
        Offset(x, y + height / 2 + 5),
        ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 7, height: height),
          const Radius.circular(2),
        ),
        ink,
      );
    }

    const trend = [
      Offset(12, 51),
      Offset(28, 40),
      Offset(43, 46),
      Offset(58, 25),
      Offset(73, 33),
      Offset(98, 16),
    ];
    switch (design) {
      case 0:
        final points = <Offset>[];
        for (var i = 0; i < 5; i++) {
          final wave = (math.sin(cycle - i * 0.7) + 1) / 2;
          final point = Offset(20 + i * 18, 46 - i * 5 - wave * 10);
          candle(point.dx, point.dy, 12 + wave * 6, 0.45 + wave * 0.55);
          points.add(point);
        }
        line(points, opacity: 0.3);
        dot(points.last, 7, 0.12);
        dot(points.last, 3, 1);
      case 1:
        line(trend, opacity: 0.12);
        final path = Path()..moveTo(trend.first.dx, trend.first.dy);
        for (final point in trend.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        final metric = path.computeMetrics().first;
        final distance = metric.length * t;
        ink
          ..style = PaintingStyle.stroke
          ..color = colors.primary;
        canvas.drawPath(metric.extractPath(0, distance), ink);
        ink.style = PaintingStyle.fill;
        final head =
            metric.getTangentForOffset(distance)?.position ?? trend.first;
        dot(head, 7, 0.12);
        dot(head, 3, 1);
      case 2:
        final points = [
          const Offset(10, 38),
          const Offset(32, 38),
          const Offset(42, 27),
          const Offset(50, 53),
          const Offset(61, 14),
          const Offset(71, 38),
          const Offset(102, 38),
        ];
        line(points, opacity: 0.18);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(t * 142 - 30, 0, 30, 72));
        line(points);
        canvas.restore();
      case 3:
        for (var i = 0; i < 6; i++) {
          final wave = (math.sin(cycle - i * 0.65) + 1) / 2;
          final height = 10 + wave * 32;
          ink.color = colors.primary.withValues(alpha: 0.3 + wave * 0.7);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(14 + i * 15, 58 - height, 9, height),
              const Radius.circular(3),
            ),
            ink,
          );
        }
      case 4:
        for (var i = 0; i < 6; i++) {
          final angle = cycle + i * math.pi / 3;
          candle(
            56 + math.cos(angle) * 30,
            36 + math.sin(angle) * 21,
            8 + (math.sin(angle) + 1) * 4,
            0.35 + (math.sin(angle) + 1) * 0.325,
          );
        }
      case 5:
        for (var i = 0; i < 3; i++) {
          final phase = (t + i / 3) % 1;
          ink
            ..style = PaintingStyle.stroke
            ..color = colors.primary.withValues(alpha: (1 - phase) * 0.55);
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(56, 45),
              width: 16 + phase * 78,
              height: 5 + phase * 25,
            ),
            ink,
          );
        }
        ink.style = PaintingStyle.fill;
        candle(56, 28 + math.sin(cycle) * 3, 17, 1);
      case 6:
        final points = [
          for (var i = 0; i <= 40; i++)
            Offset(
              10 + i * 2.3,
              36 + math.sin(i * 0.2 - cycle) * 13 - i * 0.25,
            ),
        ];
        line(points, opacity: 0.6);
        final point = points[(t * 40).floor()];
        dot(point, 8, 0.12);
        dot(point, 3.5, 1);
      case 7:
        final steps = <Offset>[const Offset(12, 57)];
        for (var i = 0; i < 5; i++) {
          steps.add(Offset(28 + i * 17, 57 - i * 9));
          steps.add(Offset(28 + i * 17, 48 - i * 9));
        }
        line(steps, opacity: 0.35);
        final step = (t * 5).floor();
        final bounce = math.sin((t * 5 % 1) * math.pi) * 12;
        dot(Offset(20 + step * 17, 48 - step * 9 - bounce), 4, 1);
      case 8:
        line(trend, opacity: 0.4);
        final x = 10 + t * 92;
        ink.color = colors.primary.withValues(alpha: 0.08);
        canvas.drawRect(Rect.fromLTWH(x - 14, 8, 28, 54), ink);
        ink.color = colors.primary.withValues(alpha: 0.8);
        canvas.drawLine(Offset(x, 8), Offset(x, 62), ink);
        for (final point in trend) {
          dot(point, 2.5, (1 - (point.dx - x).abs() / 25).clamp(0.15, 1));
        }
      case 9:
        final breath = (1 - math.cos(cycle)) / 2;
        dot(const Offset(56, 36), 20 + breath * 10, 0.06 + breath * 0.08);
        ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = colors.primary.withValues(alpha: 0.6);
        canvas.drawArc(
          Rect.fromCircle(
            center: const Offset(56, 36),
            radius: 24 + breath * 4,
          ),
          -math.pi / 2,
          math.pi * 1.65,
          false,
          ink,
        );
        ink.style = PaintingStyle.fill;
        line([
          Offset(39, 43 - breath * 2),
          const Offset(49, 36),
          const Offset(58, 40),
          Offset(72, 26 - breath * 3),
        ]);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) =>
      oldDelegate.design != design || oldDelegate.colors != colors;
}
