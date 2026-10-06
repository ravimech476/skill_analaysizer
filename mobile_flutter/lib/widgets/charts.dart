import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Charts are drawn here rather than pulled from a package: the web app does the same,
/// and three simple shapes are not worth a dependency.

class BarRow {
  BarRow(this.label, this.value, {this.caption, this.color});
  final String label;
  final double value;
  final String? caption;
  final Color? color;
}

/// Horizontal bars with the label on the left — reads better on a phone than columns.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.rows, this.max, this.suffix = '', this.labelWidth = 104});
  final List<BarRow> rows;
  final double? max;
  final String suffix;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const EmptyView('Nothing to chart yet');
    final top = max ?? rows.map((r) => r.value).fold<double>(0, math.max);
    return Column(
      children: rows.map((r) {
        final fraction = top <= 0 ? 0.0 : (r.value / top).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    if (r.caption != null)
                      Text(r.caption!, style: const TextStyle(fontSize: 11, color: Brand.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: Brand.borderSoft,
                    valueColor: AlwaysStoppedAnimation(r.color ?? Brand.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 54,
                child: Text(
                  '${r.value % 1 == 0 ? r.value.toInt() : r.value.toStringAsFixed(1)}$suffix',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// A donut with a figure in the middle, for "placed out of total" style numbers.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.value, required this.total, required this.centerLabel, this.caption, this.color = Brand.accent});
  final double value;
  final double total;
  final String centerLabel;
  final String? caption;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 132,
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _DonutPainter(total <= 0 ? 0 : (value / total).clamp(0, 1), color),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(centerLabel, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      if (caption != null)
                        Text(caption!, style: const TextStyle(fontSize: 11, color: Brand.muted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(7, 7, size.width - 14, size.height - 14);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Brand.borderSoft;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (fraction > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.fraction != fraction || old.color != color;
}

/// A sparkline-ish line chart for a trend over months.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, required this.labels, this.color = Brand.accent, this.height = 120});
  final List<double> points;
  final List<String> labels;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const EmptyView('Not enough data for a trend yet');
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(points, color)),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(labels.first, style: const TextStyle(fontSize: 11, color: Brand.muted)),
            Text(labels.last, style: const TextStyle(fontSize: 11, color: Brand.muted)),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = points.fold<double>(0, math.max);
    final minV = points.fold<double>(points.first, math.min);
    final span = (maxV - minV).abs() < 0.001 ? 1.0 : maxV - minV;
    final step = size.width / (points.length - 1);
    final path = Path();
    final fill = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * step;
      final y = size.height - ((points[i] - minV) / span) * (size.height - 12) - 6;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.points != points;
}
