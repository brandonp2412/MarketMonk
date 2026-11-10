import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Color themeWheelColor(Offset position, double size, double value) {
  final offset = position - Offset(size / 2, size / 2);
  return HSVColor.fromAHSV(
    1,
    (math.atan2(offset.dy, offset.dx) * 180 / math.pi + 360) % 360,
    (offset.distance / (size / 2)).clamp(0, 1),
    value,
  ).toColor();
}

class ThemeColorWheel extends StatefulWidget {
  const ThemeColorWheel({
    super.key,
    required this.color,
    required this.onChanged,
  });
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<ThemeColorWheel> createState() => _ThemeColorWheelState();
}

class _ThemeColorWheelState extends State<ThemeColorWheel> {
  Color? _dragColor;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _dragColor ?? widget.color;
    final hsv = HSVColor.fromColor(color);
    void update(Offset position) => setState(() {
          _dragColor = themeWheelColor(position, 200, hsv.value);
        });
    void save() {
      if (_dragColor != null) widget.onChanged(_dragColor!);
      setState(() => _dragColor = null);
    }

    return SizedBox(
      width: 240,
      child: Column(
        children: [
          Semantics(
            label: 'Color wheel. Arrow keys adjust hue and saturation.',
            child: Focus(
              focusNode: _focus,
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                var next = hsv;
                if (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight) {
                  next = hsv.withHue(
                    (hsv.hue +
                            (key == LogicalKeyboardKey.arrowRight ? 5 : -5) +
                            360) %
                        360,
                  );
                } else if (key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.arrowDown) {
                  next = hsv.withSaturation(
                    (hsv.saturation +
                            (key == LogicalKeyboardKey.arrowUp ? 0.05 : -0.05))
                        .clamp(0, 1),
                  );
                } else {
                  return KeyEventResult.ignored;
                }
                widget.onChanged(next.toColor());
                return KeyEventResult.handled;
              },
              child: GestureDetector(
                onTap: _focus.requestFocus,
                onTapDown: (event) => update(event.localPosition),
                onTapUp: (_) => save(),
                onPanStart: (event) => update(event.localPosition),
                onPanUpdate: (event) => update(event.localPosition),
                onPanEnd: (_) => save(),
                onPanCancel: () => setState(() => _dragColor = null),
                child: CustomPaint(
                  size: const Size.square(200),
                  painter: _WheelPainter(hsv),
                ),
              ),
            ),
          ),
          Slider(
            label: 'Brightness',
            value: hsv.value,
            onChanged: (value) =>
                setState(() => _dragColor = hsv.withValue(value).toColor()),
            onChangeEnd: (_) => save(),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var hue = 0; hue <= 360; hue += 60)
              HSVColor.fromAHSV(1, hue.toDouble(), 1, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HSVColor.fromAHSV(1, 0, 0, hsv.value).toColor(),
            HSVColor.fromAHSV(0, 0, 0, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );
    final angle = hsv.hue * math.pi / 180;
    final marker = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * hsv.saturation);
    canvas.drawCircle(
      marker,
      7,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      marker,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.hsv != hsv;
}
