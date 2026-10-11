import 'dart:math' as math;

import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

@immutable
class MarketDonutSlice {
  const MarketDonutSlice({
    required this.value,
    required this.color,
    required this.label,
  });

  final double value;
  final Color color;
  final String label;
}

class MarketDonutChart extends StatefulWidget {
  const MarketDonutChart({
    super.key,
    required this.slices,
    required this.selectedIndex,
    required this.onSelectionChanged,
    required this.centerSpaceRadius,
    required this.radius,
    required this.selectedRadius,
  });

  final List<MarketDonutSlice> slices;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectionChanged;
  final double centerSpaceRadius;
  final double radius;
  final double selectedRadius;

  @override
  State<MarketDonutChart> createState() => _MarketDonutChartState();
}

class _MarketDonutChartState extends State<MarketDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late List<double> _fromRadii = _targetRadii();
  late List<double> _toRadii = _targetRadii();

  List<double> _targetRadii() => List.generate(
        widget.slices.length,
        (index) => index == widget.selectedIndex
            ? widget.selectedRadius
            : widget.radius,
      );

  double _animatedRadius(int index, double progress) {
    final eased = Curves.easeOutCubic.transform(progress);
    return _fromRadii[index] + (_toRadii[index] - _fromRadii[index]) * eased;
  }

  @override
  void didUpdateWidget(covariant MarketDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targets = _targetRadii();
    if (listEquals(targets, _toRadii)) {
      return;
    }
    _fromRadii = List.generate(
      targets.length,
      (index) => index < _toRadii.length
          ? _animatedRadius(index, _selectionAnimation.value)
          : widget.radius,
    );
    _toRadii = targets;
    _selectionAnimation.forward(from: 0);
  }

  @override
  void dispose() {
    _selectionAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final center = Offset(size.width / 2, size.height / 2);

        int? hitTest(Offset position) {
          if (widget.slices.isEmpty) return null;
          final delta = position - center;
          final distance = delta.distance;

          var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
          if (angle < 0) angle += math.pi * 2;
          final total = widget.slices.fold<double>(
            0,
            (sum, slice) => sum + math.max(0, slice.value),
          );
          if (total <= 0) return null;

          var cursor = 0.0;
          var hitIndex = widget.slices.length - 1;
          for (var index = 0; index < widget.slices.length; index++) {
            cursor +=
                math.max(0, widget.slices[index].value) / total * math.pi * 2;
            if (angle <= cursor) {
              hitIndex = index;
              break;
            }
          }

          final sectionRadius = _toRadii[hitIndex];
          final availableOuter = math.min(
            widget.centerSpaceRadius + sectionRadius,
            size.shortestSide / 2,
          );
          final availableInner = math.min(
            widget.centerSpaceRadius,
            math.max(0, availableOuter - 1),
          );
          if (distance < availableInner || distance > availableOuter) {
            return null;
          }
          return hitIndex;
        }

        void select(Offset position) =>
            widget.onSelectionChanged(hitTest(position));

        return MouseRegion(
          onHover: (event) => select(event.localPosition),
          onExit: (_) => widget.onSelectionChanged(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => select(details.localPosition),
            onPanDown: (details) => select(details.localPosition),
            onPanUpdate: (details) => select(details.localPosition),
            onPanEnd: (_) => widget.onSelectionChanged(null),
            onPanCancel: () => widget.onSelectionChanged(null),
            child: DrafterTheme.brightness(
              dark: Theme.of(context).brightness == Brightness.dark,
              child: AnimatedBuilder(
                animation: _selectionAnimation,
                builder: (context, _) => ChartCanvas(
                  renderer: _MarketDonutRenderer(
                    slices: widget.slices,
                    selectedIndex: widget.selectedIndex,
                    centerSpaceRadius: widget.centerSpaceRadius,
                    sectionRadii: List.generate(
                      _toRadii.length,
                      (index) =>
                          _animatedRadius(index, _selectionAnimation.value),
                    ),
                  ),
                  animate: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MarketDonutRenderer extends ChartRenderer {
  const _MarketDonutRenderer({
    required this.slices,
    required this.selectedIndex,
    required this.centerSpaceRadius,
    required this.sectionRadii,
  });

  final List<MarketDonutSlice> slices;
  final int? selectedIndex;
  final double centerSpaceRadius;
  final List<double> sectionRadii;

  @override
  void draw(
    Canvas canvas,
    Size size,
    DrafterThemeColors theme,
    double progress,
  ) {
    if (slices.isEmpty || size.isEmpty) return;
    final total = slices.fold<double>(
      0,
      (sum, slice) => sum + math.max(0, slice.value),
    );
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxOuter = size.shortestSide / 2;
    var startAngle = -math.pi / 2;

    for (var index = 0; index < slices.length; index++) {
      final slice = slices[index];
      final sweep = math.max(0, slice.value) / total * math.pi * 2 * progress;
      final sectionRadius = sectionRadii[index];
      final outer = math.min(centerSpaceRadius + sectionRadius, maxOuter);
      final inner = math.min(centerSpaceRadius, math.max(0, outer - 1));
      final strokeWidth = math.max(1.0, outer - inner);
      final ringRadius = inner + strokeWidth / 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        startAngle,
        sweep,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true,
      );

      if (index == selectedIndex && sweep > 0.16) {
        final midAngle = startAngle + sweep / 2;
        final labelRadius = inner + strokeWidth * 0.55;
        final point = center +
            Offset(
              math.cos(midAngle) * labelRadius,
              math.sin(midAngle) * labelRadius,
            );
        final brightness = ThemeData.estimateBrightnessForColor(slice.color);
        drawChartText(
          canvas,
          '${(slice.value / total * 100).toStringAsFixed(1)}%',
          point,
          color: brightness == Brightness.dark ? Colors.white : Colors.black,
          fontSize: 12,
          h: HAlign.center,
          v: VAlign.center,
        );
      }

      startAngle += math.max(0, slice.value) / total * math.pi * 2;
    }
  }

  @override
  String get accessibilityLabel => 'Portfolio allocation';

  @override
  String get accessibilityValue {
    final total = slices.fold<double>(
      0,
      (sum, slice) => sum + math.max(0, slice.value),
    );
    if (total <= 0) return 'No allocation data';
    return slices
        .map(
          (slice) =>
              '${slice.label} ${(slice.value / total * 100).toStringAsFixed(1)}%',
        )
        .join(', ');
  }
}
