import 'dart:math' as math;

import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
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

class MarketDonutChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final center = Offset(size.width / 2, size.height / 2);

        int? hitTest(Offset position) {
          if (slices.isEmpty) return null;
          final delta = position - center;
          final distance = delta.distance;

          var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
          if (angle < 0) angle += math.pi * 2;
          final total = slices.fold<double>(
            0,
            (sum, slice) => sum + math.max(0, slice.value),
          );
          if (total <= 0) return null;

          var cursor = 0.0;
          var hitIndex = slices.length - 1;
          for (var index = 0; index < slices.length; index++) {
            cursor += math.max(0, slices[index].value) / total * math.pi * 2;
            if (angle <= cursor) {
              hitIndex = index;
              break;
            }
          }

          final sectionRadius =
              hitIndex == selectedIndex ? selectedRadius : radius;
          final availableOuter = math.min(
            centerSpaceRadius + sectionRadius,
            size.shortestSide / 2,
          );
          final availableInner = math.min(
            centerSpaceRadius,
            math.max(0, availableOuter - 1),
          );
          if (distance < availableInner || distance > availableOuter) {
            return null;
          }
          return hitIndex;
        }

        void select(Offset position) => onSelectionChanged(hitTest(position));

        return MouseRegion(
          onHover: (event) => select(event.localPosition),
          onExit: (_) => onSelectionChanged(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => select(details.localPosition),
            onPanDown: (details) => select(details.localPosition),
            onPanUpdate: (details) => select(details.localPosition),
            onPanEnd: (_) => onSelectionChanged(null),
            onPanCancel: () => onSelectionChanged(null),
            child: DrafterTheme.brightness(
              dark: Theme.of(context).brightness == Brightness.dark,
              child: ChartCanvas(
                renderer: _MarketDonutRenderer(
                  slices: slices,
                  selectedIndex: selectedIndex,
                  centerSpaceRadius: centerSpaceRadius,
                  radius: radius,
                  selectedRadius: selectedRadius,
                ),
                animate: false,
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
    required this.radius,
    required this.selectedRadius,
  });

  final List<MarketDonutSlice> slices;
  final int? selectedIndex;
  final double centerSpaceRadius;
  final double radius;
  final double selectedRadius;

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
      final sectionRadius = index == selectedIndex ? selectedRadius : radius;
      final outer = math.min(centerSpaceRadius + sectionRadius, maxOuter);
      final inner = math.min(
        centerSpaceRadius,
        math.max(0, outer - 1),
      );
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
