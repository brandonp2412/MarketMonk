import 'package:flutter/material.dart';

class PortfolioPeriodPicker extends StatelessWidget {
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;

  const PortfolioPeriodPicker({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labels[value], style: theme.textTheme.labelLarge),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            trackShape: const _DottedPeriodTrack(),
            tickMarkShape: SliderTickMarkShape.noTickMark,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.outline,
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            key: const Key('portfolio-return-period'),
            value: value.toDouble(),
            max: labels.length > 1 ? (labels.length - 1).toDouble() : 1,
            divisions: labels.length > 1 ? labels.length - 1 : null,
            label: labels[value],
            semanticFormatterCallback: (value) =>
                labels[value.round().clamp(0, labels.length - 1)],
            onChanged:
                labels.length > 1 ? (value) => onChanged(value.round()) : null,
          ),
        ),
      ],
    );
  }
}

class _DottedPeriodTrack extends RoundedRectSliderTrackShape {
  const _DottedPeriodTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final count = (track.width / 8).floor();
    if (count < 1) return;
    final paint = Paint();
    for (var index = 0; index <= count; index++) {
      final x = track.left + track.width * index / count;
      final active = textDirection == TextDirection.ltr
          ? x <= thumbCenter.dx
          : x >= thumbCenter.dx;
      paint.color = isEnabled && active
          ? sliderTheme.activeTrackColor!
          : sliderTheme.inactiveTrackColor!.withValues(alpha: 0.5);
      context.canvas.drawCircle(Offset(x, track.center.dy), 1.5, paint);
    }
  }
}
