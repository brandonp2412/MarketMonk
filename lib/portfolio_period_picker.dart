import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

class PortfolioPeriodPicker extends StatelessWidget {
  final List<String> labels;
  final List<DateTime?> dates;
  final int value;
  final ValueChanged<int> onChanged;

  const PortfolioPeriodPicker({
    super.key,
    required this.labels,
    required this.dates,
    required this.value,
    required this.onChanged,
  })  : assert(labels.length == dates.length),
        assert(labels.length > 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedDate = dates[value];
    final title = selectedDate == null
        ? 'Now'
        : DateFormat(
            labels[value].endsWith('H') ? 'd MMM yyyy, h:mm a' : 'd MMM yyyy',
          ).format(selectedDate);
    final oldestDate = dates.last;
    final oldestLabel = oldestDate == null
        ? 'NOW'
        : DateFormat(labels.last.endsWith('H') ? 'd MMM h:mm a' : 'MMM yyyy')
            .format(oldestDate)
            .toUpperCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 18,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'WHEN',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (selectedDate == null) ...[
              Icon(Icons.adjust_rounded, size: 14, color: colors.primary),
              const SizedBox(width: 4),
            ],
            Text(
              selectedDate == null
                  ? 'PRESENT'
                  : labels[value] == 'Inception'
                      ? 'INCEPTION'
                      : '${labels[value]} AGO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          title,
          key: const Key('portfolio-time-title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          selectedDate == null
              ? 'Current allocation · total P/L'
              : 'Allocation then · returns since this date',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 22,
            trackShape: _TimeRulerTrack(
              stops: labels.length,
              lineColor: colors.outlineVariant,
              tickColor: colors.onSurfaceVariant,
              selectedColor: colors.primary,
            ),
            tickMarkShape: SliderTickMarkShape.noTickMark,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: colors.outlineVariant,
            inactiveTrackColor: colors.outlineVariant,
            thumbColor: colors.primary,
          ),
          child: Slider(
            key: const Key('portfolio-return-period'),
            value: value.toDouble(),
            max: labels.length > 1 ? (labels.length - 1).toDouble() : 1,
            divisions: labels.length > 1 ? labels.length - 1 : null,
            label: title,
            semanticFormatterCallback: (position) {
              final index = position.round().clamp(0, labels.length - 1);
              final date = dates[index];
              return date == null
                  ? 'Now, current allocation'
                  : '${DateFormat.yMMMMd().format(date)}, ${labels[index]}${labels[index] == 'Inception' ? '' : ' ago'}';
            },
            onChanged: labels.length > 1
                ? (position) => onChanged(position.round())
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                'NOW',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.9,
                ),
              ),
              const Spacer(),
              Text(
                'FURTHEST · $oldestLabel',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeRulerTrack extends RoundedRectSliderTrackShape {
  final int stops;
  final Color lineColor;
  final Color tickColor;
  final Color selectedColor;

  const _TimeRulerTrack({
    required this.stops,
    required this.lineColor,
    required this.tickColor,
    required this.selectedColor,
  });

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
    final canvas = context.canvas;
    final center = track.center.dy;
    final neutral = lineColor.withValues(alpha: isEnabled ? 0.75 : 0.3);
    canvas.drawLine(
      Offset(track.left, center),
      Offset(track.right, center),
      Paint()
        ..color = neutral
        ..strokeWidth = 1,
    );
    if (stops > 1) {
      final selectedIndex =
          ((thumbCenter.dx - track.left) / track.width * (stops - 1))
              .round()
              .clamp(0, stops - 1);
      for (var index = 0; index < stops; index++) {
        final x = track.left + track.width * index / (stops - 1);
        if (index != selectedIndex) {
          final height = index == 0 || index == stops - 1 ? 13.0 : 9.0;
          canvas.drawLine(
            Offset(x, center - height / 2),
            Offset(x, center + height / 2),
            Paint()
              ..color = tickColor.withValues(alpha: 0.6)
              ..strokeWidth = 1.5
              ..strokeCap = StrokeCap.round,
          );
        }
        if (index == stops - 1) continue;
        for (var sub = 1; sub < 4; sub++) {
          final minorX = x + track.width * sub / ((stops - 1) * 4);
          canvas.drawLine(
            Offset(minorX, center - 2),
            Offset(minorX, center + 2),
            Paint()
              ..color = neutral
              ..strokeWidth = 1,
          );
        }
      }
    }
    canvas.drawLine(
      Offset(thumbCenter.dx, center - 16),
      Offset(thumbCenter.dx, center + 16),
      Paint()
        ..color = selectedColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }
}
