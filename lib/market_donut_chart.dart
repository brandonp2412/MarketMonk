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

@immutable
class _MarketDonutArc {
  const _MarketDonutArc({
    required this.label,
    required this.color,
    required this.startAngle,
    required this.sweep,
    required this.radius,
  });

  final String label;
  final Color color;
  final double startAngle;
  final double sweep;
  final double radius;

  _MarketDonutArc withSweep(double nextSweep) => _MarketDonutArc(
        label: label,
        color: color,
        startAngle: startAngle,
        sweep: nextSweep,
        radius: radius,
      );
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
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late Map<String, _MarketDonutArc> _fromArcs = _targetArcs();
  late Map<String, _MarketDonutArc> _toArcs = _targetArcs();

  Map<String, _MarketDonutArc> _targetArcs() {
    final total = widget.slices.fold<double>(
      0,
      (sum, slice) => sum + math.max(0, slice.value),
    );
    var startAngle = -math.pi / 2;
    final arcs = <String, _MarketDonutArc>{};
    for (var index = 0; index < widget.slices.length; index++) {
      final slice = widget.slices[index];
      final sweep =
          total <= 0 ? 0.0 : math.max(0, slice.value) / total * math.pi * 2;
      arcs[slice.label] = _MarketDonutArc(
        label: slice.label,
        color: slice.color,
        startAngle: startAngle,
        sweep: sweep,
        radius: index == widget.selectedIndex
            ? widget.selectedRadius
            : widget.radius,
      );
      startAngle += sweep;
    }
    return arcs;
  }

  bool _sameArcs(
    Map<String, _MarketDonutArc> first,
    Map<String, _MarketDonutArc> second,
  ) {
    if (first.length != second.length) return false;
    for (final entry in first.entries) {
      final other = second[entry.key];
      if (other == null ||
          entry.value.startAngle != other.startAngle ||
          entry.value.sweep != other.sweep ||
          entry.value.radius != other.radius ||
          entry.value.color != other.color) {
        return false;
      }
    }
    return true;
  }

  _MarketDonutArc _animatedArc(String label, double eased) {
    final from = _fromArcs[label] ?? _toArcs[label]!.withSweep(0);
    final to = _toArcs[label] ?? _fromArcs[label]!.withSweep(0);
    double between(double a, double b) => a + (b - a) * eased;
    return _MarketDonutArc(
      label: label,
      color: Color.lerp(from.color, to.color, eased)!,
      startAngle: between(from.startAngle, to.startAngle),
      sweep: between(from.sweep, to.sweep),
      radius: between(from.radius, to.radius),
    );
  }

  List<_MarketDonutArc> _animatedArcs(double progress) {
    final eased = Curves.easeOutCubic.transform(progress);
    return [
      for (final label in {..._toArcs.keys, ..._fromArcs.keys})
        _animatedArc(label, eased),
    ];
  }

  @override
  void didUpdateWidget(covariant MarketDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targets = _targetArcs();
    if (_sameArcs(targets, _toArcs)) return;
    _fromArcs = {
      for (final arc in _animatedArcs(_selectionAnimation.value))
        if (arc.sweep > 0.000001) arc.label: arc,
    };
    _toArcs = targets;
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

          var angle = math.atan2(delta.dy, delta.dx);
          if (angle < -math.pi / 2) angle += math.pi * 2;
          final arcs = _animatedArcs(_selectionAnimation.value);
          for (final arc in arcs.reversed) {
            if (angle < arc.startAngle || angle >= arc.startAngle + arc.sweep) {
              continue;
            }
            final availableOuter = math.min(
              widget.centerSpaceRadius + arc.radius,
              size.shortestSide / 2,
            );
            final availableInner = math.min(
              widget.centerSpaceRadius,
              math.max(0, availableOuter - 1),
            );
            if (distance >= availableInner && distance <= availableOuter) {
              final index = widget.slices.indexWhere(
                (slice) => slice.label == arc.label,
              );
              return index < 0 ? null : index;
            }
          }
          return null;
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
                    arcs: _animatedArcs(_selectionAnimation.value),
                    selectedLabel: widget.selectedIndex == null ||
                            widget.selectedIndex! >= widget.slices.length
                        ? null
                        : widget.slices[widget.selectedIndex!].label,
                    centerSpaceRadius: widget.centerSpaceRadius,
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
    required this.arcs,
    required this.selectedLabel,
    required this.centerSpaceRadius,
  });

  final List<MarketDonutSlice> slices;
  final List<_MarketDonutArc> arcs;
  final String? selectedLabel;
  final double centerSpaceRadius;

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

    for (final arc in arcs) {
      final sweep = arc.sweep * progress;
      if (sweep <= 0) continue;
      final outer = math.min(centerSpaceRadius + arc.radius, maxOuter);
      final inner = math.min(centerSpaceRadius, math.max(0, outer - 1));
      final strokeWidth = math.max(1.0, outer - inner);
      final ringRadius = inner + strokeWidth / 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        arc.startAngle,
        sweep,
        false,
        Paint()
          ..color = arc.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true,
      );

      if (arc.label == selectedLabel && sweep > 0.16) {
        final midAngle = arc.startAngle + sweep / 2;
        final labelRadius = inner + strokeWidth * 0.55;
        final point = center +
            Offset(
              math.cos(midAngle) * labelRadius,
              math.sin(midAngle) * labelRadius,
            );
        final brightness = ThemeData.estimateBrightnessForColor(arc.color);
        drawChartText(
          canvas,
          '${(arc.sweep / (math.pi * 2) * 100).toStringAsFixed(1)}%',
          point,
          color: brightness == Brightness.dark ? Colors.white : Colors.black,
          fontSize: 12,
          h: HAlign.center,
          v: VAlign.center,
        );
      }
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
