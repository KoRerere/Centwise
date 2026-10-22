import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components.dart';
import 'motion.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Monotone cubic path through points (Fritsch–Carlson), matching Swift Charts' `.monotone`.
Path monotonePath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  final n = points.length;
  final slopes = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = points[i + 1].dx - points[i].dx;
    slopes[i] = dx == 0 ? 0 : (points[i + 1].dy - points[i].dy) / dx;
  }
  final tangents = List<double>.filled(n, 0);
  tangents[0] = slopes[0];
  tangents[n - 1] = slopes[n - 2];
  for (var i = 1; i < n - 1; i++) {
    tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (slopes[i] == 0) {
      tangents[i] = 0;
      tangents[i + 1] = 0;
      continue;
    }
    final a = tangents[i] / slopes[i];
    final b = tangents[i + 1] / slopes[i];
    final h = a * a + b * b;
    if (h > 9) {
      final t = 3 / math.sqrt(h);
      tangents[i] = t * a * slopes[i];
      tangents[i + 1] = t * b * slopes[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final p0 = points[i];
    final p1 = points[i + 1];
    final dx = (p1.dx - p0.dx) / 3;
    path.cubicTo(p0.dx + dx, p0.dy + tangents[i] * dx, p1.dx - dx, p1.dy - tangents[i + 1] * dx, p1.dx, p1.dy);
  }
  return path;
}

Path _dashed(Path source, {double dash = 3, double gap = 4}) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      result.addPath(metric.extractPath(distance, math.min(distance + dash, metric.length)), Offset.zero);
      distance += dash + gap;
    }
  }
  return result;
}

/// Cumulative spend line (this period, solid brand blue) against the previous period (grey dashed),
/// with an endpoint dot and optional time ticks underneath.
class CumulativeChart extends StatelessWidget {
  const CumulativeChart({
    super.key,
    required this.current,
    required this.previous,
    required this.domainMax,
    this.ticks = const [],
    this.height = 112,
  });

  /// Values indexed by step (index 0 is the first step).
  final List<double> current;
  final List<double> previous;

  /// Number of steps across the full width.
  final int domainMax;

  /// Evenly spaced labels under the chart, first to last (e.g. 00:00 · 12:00 · 24:00).
  final List<String> ticks;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // This period is always solid black (ink); the previous one a grey dashed line. How it compares is
    // said in words above the chart, not with a coloured badge.
    final color = p.brand;
    final chart = SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxValue = [...current, ...previous, 1.0].reduce(math.max);
        Offset at(int index, double value) => Offset(
              domainMax <= 1 ? 0 : index / (domainMax - 1) * width,
              height - 4 - (value / maxValue) * (height - 12),
            );
        return CustomPaint(
          size: Size(width, height),
          painter: _CumulativePainter(
            current: [for (var i = 0; i < current.length; i++) at(i, current[i])],
            previous: [for (var i = 0; i < previous.length; i++) at(i, previous[i])],
            color: color,
            muted: p.muted.withValues(alpha: 0.55),
            baseline: p.track,
          ),
        );
      }),
    );
    if (ticks.isEmpty) return chart;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      chart,
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < ticks.length; i++)
          Expanded(
            child: Text(
              ticks[i],
              textAlign: i == 0 ? TextAlign.left : (i == ticks.length - 1 ? TextAlign.right : TextAlign.center),
              style: cw(11, color: p.muted),
            ),
          ),
      ]),
    ]);
  }
}

class _CumulativePainter extends CustomPainter {
  _CumulativePainter({required this.current, required this.previous, required this.color, required this.muted, required this.baseline});
  final List<Offset> current;
  final List<Offset> previous;
  final Color color;
  final Color muted;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    // Zero line, so the start and the scale read clearly.
    canvas.drawLine(Offset(0, size.height - 4), Offset(size.width, size.height - 4), Paint()..color = baseline..strokeWidth = 1);
    if (previous.length > 1) {
      canvas.drawPath(
        _dashed(monotonePath(previous)),
        Paint()
          ..color = muted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (current.length > 1) {
      canvas.drawPath(
        monotonePath(current),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (current.isNotEmpty) canvas.drawCircle(current.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CumulativePainter old) =>
      old.current != current || old.previous != previous || old.color != color || old.baseline != baseline;
}

/// Twelve monthly bars with a dashed monthly-average line.
class MonthBarsChart extends StatelessWidget {
  const MonthBarsChart({super.key, required this.values, required this.labels, required this.average, required this.highlight, this.height = 150});
  final List<int> values;
  final List<String> labels;
  final int average;
  final int highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final maxValue = math.max(values.fold<int>(average, math.max), 1).toDouble();
    const labelHeight = 18.0;
    final plot = height - labelHeight;
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final averageY = plot - (average / maxValue) * (plot - 12);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    FractionallySizedBox(
                      widthFactor: 0.62,
                      child: Container(
                        height: math.max(0.0, values[i] / maxValue * (plot - 12)),
                        decoration: BoxDecoration(
                          color: i == highlight
                              ? p.brand
                              : p.ink.withValues(alpha: values[i] > average ? 0.32 : 0.14),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: labelHeight,
                      child: Center(child: Text(labels[i], style: cw(10, weight: FontWeight.w600, color: p.muted))),
                    ),
                  ]),
                ),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: averageY,
            child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashLinePainter(p.ink.withValues(alpha: 0.7))),
          ),
          Positioned(
            right: 0,
            top: math.max(0.0, averageY - 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('月均 '), style: cw(10, weight: FontWeight.w700, color: p.card)),
                AmountText(average, size: 10, weight: FontWeight.w700, sign: '', color: p.card),
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}

class _DashLinePainter extends CustomPainter {
  _DashLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter old) => old.color != color;
}

/// Category donut.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.size = 92, this.thickness = 13});
  final List<(double, Color)> slices;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DonutPainter(slices, p.track, thickness)),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.track, this.thickness);
  final List<(double, Color)> slices;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - thickness / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final total = slices.fold<double>(0, (s, e) => s + e.$1);
    if (total <= 0) return;
    const gap = 0.035;
    var start = -math.pi / 2;
    for (final (value, color) in slices) {
      final sweep = value / total * math.pi * 2;
      if (sweep > gap * 1.5) {
        canvas.drawArc(rect, start + gap / 2, sweep - gap, false, base..color = color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices || old.track != track;
}

/// Six-month grouped income / expense bars with dashed grid lines, with its own legend on top.
/// Tap a month to select it (the others dim) and the legend row turns into that month's figures, like
/// the Health app's charts; tap it again, or the empty part of the chart, to go back.
class TrendChart extends StatefulWidget {
  const TrendChart(
      {super.key, required this.labels, required this.income, required this.expense, this.titles, this.height = 190});
  final List<String> labels;

  /// Longer month names for the selected-month header, e.g. "2026年10月"; falls back to [labels].
  final List<String>? titles;
  final List<int> income;
  final List<int> expense;
  final double height;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;

  static const double _barWidth = 20;
  static const double _barGap = 4;
  static const double _labelHeight = 20;
  static const double _headerHeight = 40;

  void _tap(int? index) {
    if (index == null && _selected == null) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = index == null || _selected == index ? null : index);
  }

  @override
  void didUpdateWidget(covariant TrendChart old) {
    super.didUpdateWidget(old);
    if (_selected != null && _selected! >= widget.labels.length) _selected = null;
  }

  Widget _legendItem(Palette p, String title, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(title, style: cw(12, weight: FontWeight.w600, color: p.muted)),
      ]);

  Widget _header(Palette p) {
    final selected = _selected;
    final Widget child;
    if (selected == null) {
      child = Align(
        key: const ValueKey('legend'),
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _legendItem(p, tr('收入'), p.income),
          const SizedBox(width: 14),
          _legendItem(p, tr('支出'), p.brand),
        ]),
      );
    } else {
      final income = widget.income[selected];
      final expense = widget.expense[selected];
      Widget figure(String label, Color? dot, int cents) => Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
            ],
            Text(label, style: cw(12, color: p.muted)),
            const SizedBox(width: 4),
            AmountText(cents, size: 14, weight: FontWeight.w600, color: p.ink),
          ]);
      child = Column(
        key: ValueKey(selected),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text((widget.titles ?? widget.labels)[selected], style: cw(12, weight: FontWeight.w600, color: p.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              figure(tr('收入'), p.income, income),
              const SizedBox(width: 12),
              figure(tr('支出'), p.brand, expense),
              const SizedBox(width: 12),
              figure(tr('结余'), null, income - expense),
            ]),
          ),
        ],
      );
    }
    return SizedBox(
      height: _headerHeight,
      child: AnimatedSwitcher(
        duration: IOSMotion.snappyCurve.duration,
        switchInCurve: IOSMotion.snappyCurve,
        switchOutCurve: IOSMotion.snappyCurve,
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final income = widget.income;
    final expense = widget.expense;
    final count = widget.labels.length;
    final maxValue = math.max([...income, ...expense].fold<int>(0, math.max), 1).toDouble();
    final plot = widget.height - _labelHeight;
    final usable = plot - 4;
    double barHeight(int v) => math.max(0.0, v / maxValue * usable);
    final selected = _selected;

    Widget bar(int value, Color color) => Container(
          width: _barWidth,
          height: barHeight(value),
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(p),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final column = constraints.maxWidth / count;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap((d.localPosition.dx / column).floor().clamp(0, count - 1)),
          child: SizedBox(
            height: widget.height,
            child: Stack(children: [
              // Selected month: a soft highlight behind its bars.
              if (selected != null)
                Positioned(
                  left: column * selected + 4,
                  width: column - 8,
                  top: 0,
                  height: plot,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: p.track.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              for (final fraction in const [0.0, 0.5, 1.0])
                Positioned(
                  left: 0,
                  right: 0,
                  top: plot - fraction * usable,
                  child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashLinePainter(p.track)),
                ),
              Positioned.fill(
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: AnimatedOpacity(
                        duration: IOSMotion.snappyCurve.duration,
                        curve: IOSMotion.snappyCurve,
                        opacity: selected == null || selected == i ? 1 : 0.35,
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            bar(income[i], p.income),
                            const SizedBox(width: _barGap),
                            bar(expense[i], p.brand),
                          ]),
                          SizedBox(
                            height: _labelHeight,
                            child: Center(
                              child: Text(widget.labels[i],
                                  style: cw(12,
                                      weight: selected == i ? FontWeight.w600 : FontWeight.w400,
                                      color: selected == i ? p.ink : p.muted)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        );
      }),
    ]);
  }
}
