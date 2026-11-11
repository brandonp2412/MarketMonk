part of '../market_line_chart.dart';

void _drawNeonDot(
  Canvas canvas, {
  required Offset center,
  required Color color,
  required Color surface,
  required double radius,
}) {
  final dark = surface.computeLuminance() < 0.5;
  final glowRadius = radius * 1.8;
  final highlight = Color.lerp(color, Colors.white, dark ? 0.65 : 0.4)!;
  canvas.drawCircle(
    center,
    glowRadius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: dark ? 0.4 : 0.24),
          color.withValues(alpha: 0.12),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
  );
  canvas.drawCircle(center, radius, Paint()..color = surface);
  canvas.drawCircle(
    center,
    radius - 0.75,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [highlight, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
  canvas.drawCircle(
    center,
    radius * 0.48,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [highlight, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.48)),
  );
}

void _drawMarketTooltip(
  Canvas canvas, {
  required Offset anchor,
  required Size container,
  required List<TooltipRow> rows,
  required Color background,
  required Color textColor,
  required Color mutedTextColor,
  String? title,
}) {
  final hasTitle = title != null && title.isNotEmpty;
  if (rows.isEmpty && !hasTitle) return;

  var maxWidth = 0.0;
  if (hasTitle) {
    maxWidth = measureChartText(
      title,
      color: textColor,
      fontSize: _tooltipFontSize,
    );
  }
  for (final row in rows) {
    final textWidth = measureChartText(
      row.text,
      color: textColor,
      fontSize: _tooltipFontSize,
    );
    final rowWidth = textWidth +
        (row.swatch == null ? 0 : _tooltipSwatchSize + _tooltipSwatchGap);
    maxWidth = max(maxWidth, rowWidth);
  }

  final titleHeight = hasTitle ? _tooltipRowHeight : 0.0;
  final boxWidth = maxWidth + _tooltipPadding * 2;
  final boxHeight =
      titleHeight + rows.length * _tooltipRowHeight + _tooltipPadding * 2;
  var left = anchor.dx + 12;
  if (left + boxWidth > container.width) {
    left = anchor.dx - 12 - boxWidth;
  }
  left = left.clamp(0.0, max(0.0, container.width - boxWidth)).toDouble();
  final top =
      anchor.dy.clamp(0.0, max(0.0, container.height - boxHeight)).toDouble();

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxWidth, boxHeight),
      const Radius.circular(8),
    ),
    Paint()..color = background,
  );

  var rowTop = top + _tooltipPadding;
  if (hasTitle) {
    drawChartText(
      canvas,
      title,
      Offset(left + _tooltipPadding, rowTop + _tooltipRowHeight / 2),
      color: mutedTextColor,
      fontSize: _tooltipFontSize,
      v: VAlign.center,
    );
    rowTop += _tooltipRowHeight;
  }
  for (final row in rows) {
    final rowCenter = rowTop + _tooltipRowHeight / 2;
    var textX = left + _tooltipPadding;
    if (row.swatch case final color?) {
      _drawNeonDot(
        canvas,
        center: Offset(textX + _tooltipSwatchSize / 2, rowCenter),
        color: color,
        surface: background,
        radius: _tooltipSwatchSize / 2,
      );
      textX += _tooltipSwatchSize + _tooltipSwatchGap;
    }
    drawChartText(
      canvas,
      row.text,
      Offset(textX, rowCenter),
      color: textColor,
      fontSize: _tooltipFontSize,
      v: VAlign.center,
    );
    rowTop += _tooltipRowHeight;
  }
}

(double, double) _calculateYBounds(List<MarketLineChartPoint> points) {
  if (points.isEmpty) return (0, 1);

  var minY = points.map((point) => point.y).reduce(min);
  var maxY = points.map((point) => point.y).reduce(max);
  if (maxY - minY < 1.0) {
    final center = (maxY + minY) / 2;
    minY = center - 0.5;
    maxY = center + 0.5;
  }

  final padding = (maxY - minY) * _lineChartEdgePaddingFraction;
  return (minY - padding, maxY + padding);
}
