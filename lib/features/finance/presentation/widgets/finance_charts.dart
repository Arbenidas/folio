import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';

enum FinanceChartKind { waterfall, pie, daily }

/// Donut / Pie chart showing monthly expense distribution with interactive
/// hover highlighting and center total.
class FinancePieChart extends StatefulWidget {
  const FinancePieChart({
    super.key,
    required this.breakdown,
    required this.totalExpense,
    required this.symbol,
    required this.hide,
  });

  final List<CategorySpending> breakdown;
  final double totalExpense;
  final String symbol;
  final bool hide;

  @override
  State<FinancePieChart> createState() => _FinancePieChartState();
}

class _FinancePieChartState extends State<FinancePieChart> {
  int? _hoveredIndex;

  Color _sliceColor(int index, ColorScheme colors, FinancePalette palette) {
    final shades = <Color>[
      palette.negative,
      palette.negative.withValues(alpha: 0.72),
      colors.onSurface,
      colors.onSurfaceVariant,
      palette.negative.withValues(alpha: 0.48),
      colors.onSurfaceVariant.withValues(alpha: 0.55),
    ];
    return shades[index % shades.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    if (widget.breakdown.isEmpty || widget.totalExpense <= 0) {
      return Center(
        child: Text(
          'Registra gastos para ver la gráfica de pastel.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      );
    }

    final activeItem =
        _hoveredIndex != null && _hoveredIndex! < widget.breakdown.length
        ? widget.breakdown[_hoveredIndex!]
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final chartSize = compact ? 156.0 : 178.0;
        final donut = SizedBox(
          width: chartSize,
          height: chartSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(chartSize),
                painter: _DonutPainter(
                  items: widget.breakdown,
                  sliceColors: [
                    for (var i = 0; i < widget.breakdown.length; i++)
                      _sliceColor(i, colors, palette),
                  ],
                  hoveredIndex: _hoveredIndex,
                  separatorColor: palette.cardBg,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeItem?.category.name ?? 'Total gastos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FinanceFormat.money(
                        activeItem?.spent ?? widget.totalExpense,
                        symbol: widget.symbol,
                        hide: widget.hide,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (activeItem != null && _hoveredIndex != null)
                      Text(
                        '${(activeItem.share * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _sliceColor(_hoveredIndex!, colors, palette),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        final legend = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < math.min(6, widget.breakdown.length); i++)
              _buildLegendRow(i, widget.breakdown[i], colors, palette),
          ],
        );

        if (compact) {
          return Column(
            children: [
              donut,
              const SizedBox(height: 12),
              legend,
            ],
          );
        }
        return Row(
          children: [
            donut,
            const SizedBox(width: 22),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  Widget _buildLegendRow(
    int index,
    CategorySpending item,
    ColorScheme colors,
    FinancePalette palette,
  ) {
    final hovered = _hoveredIndex == index;
    final tint = _sliceColor(index, colors, palette);
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() {
        if (_hoveredIndex == index) _hoveredIndex = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: hovered
              ? colors.surfaceContainerHigh.withValues(alpha: 0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item.category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hovered ? FontWeight.w700 : FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ),
            Text(
              '${(item.share * 100).round()}%',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              FinanceFormat.money(
                item.spent,
                symbol: widget.symbol,
                hide: widget.hide,
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.items,
    required this.sliceColors,
    required this.hoveredIndex,
    required this.separatorColor,
  });

  final List<CategorySpending> items;
  final List<Color> sliceColors;
  final int? hoveredIndex;
  final Color separatorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseStroke = size.width * 0.16;
    final baseRadius = (size.width / 2) - baseStroke / 2 - 4;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final sweep = (item.share * 2 * math.pi).clamp(0.03, 2 * math.pi);
      final isHovered = hoveredIndex == i;
      final stroke = isHovered ? baseStroke + 5 : baseStroke;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = sliceColors[i].withValues(
          alpha: hoveredIndex == null || isHovered ? 1.0 : 0.45,
        );

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: baseRadius),
        startAngle,
        sweep,
        false,
        paint,
      );

      if (items.length > 1) {
        final sepAngle = startAngle;
        final inner = Offset(
          center.dx + (baseRadius - stroke / 2 - 1) * math.cos(sepAngle),
          center.dy + (baseRadius - stroke / 2 - 1) * math.sin(sepAngle),
        );
        final outer = Offset(
          center.dx + (baseRadius + stroke / 2 + 1) * math.cos(sepAngle),
          center.dy + (baseRadius + stroke / 2 + 1) * math.sin(sepAngle),
        );
        canvas.drawLine(
          inner,
          outer,
          Paint()
            ..color = separatorColor
            ..strokeWidth = 2.2,
        );
      }

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.items != items ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.separatorColor != separatorColor;
}

/// Waterfall (Cascada) chart: Ingresos -> top expense drops -> Flujo neto.
class FinanceWaterfallChart extends StatelessWidget {
  const FinanceWaterfallChart({
    super.key,
    required this.income,
    required this.breakdown,
    required this.symbol,
    required this.hide,
  });

  final double income;
  final List<CategorySpending> breakdown;
  final String symbol;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    if (income <= 0 && breakdown.isEmpty) {
      return Center(
        child: Text(
          'Registra ingresos y gastos para ver la cascada del mes.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      );
    }

    final steps = <_WaterfallStep>[];
    var running = income;
    steps.add(
      _WaterfallStep(
        label: 'Ingresos',
        start: 0,
        end: income,
        delta: income,
        color: palette.positive,
        isTotal: true,
      ),
    );

    final topCats = breakdown.take(4).toList();
    final rest = breakdown.skip(4).fold<double>(0, (sum, c) => sum + c.spent);
    final dropColors = <Color>[
      palette.negative,
      palette.negative.withValues(alpha: 0.78),
      palette.negative.withValues(alpha: 0.58),
      colors.onSurfaceVariant,
    ];
    for (var i = 0; i < topCats.length; i++) {
      final item = topCats[i];
      final next = running - item.spent;
      steps.add(
        _WaterfallStep(
          label: item.category.name,
          start: running,
          end: next,
          delta: -item.spent,
          color: dropColors[i % dropColors.length],
          isTotal: false,
        ),
      );
      running = next;
    }
    if (rest > 0) {
      final next = running - rest;
      steps.add(
        _WaterfallStep(
          label: 'Otros',
          start: running,
          end: next,
          delta: -rest,
          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
          isTotal: false,
        ),
      );
      running = next;
    }

    steps.add(
      _WaterfallStep(
        label: 'Neto',
        start: 0,
        end: running,
        delta: running,
        color: running >= 0 ? palette.positive : palette.negative,
        isTotal: true,
      ),
    );

    return CustomPaint(
      size: Size.infinite,
      painter: _WaterfallPainter(
        steps: steps,
        symbol: symbol,
        hide: hide,
        textColor: colors.onSurface,
        mutedColor: colors.onSurfaceVariant,
        gridColor: colors.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _WaterfallStep {
  const _WaterfallStep({
    required this.label,
    required this.start,
    required this.end,
    required this.delta,
    required this.color,
    required this.isTotal,
  });

  final String label;
  final double start;
  final double end;
  final double delta;
  final Color color;
  final bool isTotal;
}

class _WaterfallPainter extends CustomPainter {
  const _WaterfallPainter({
    required this.steps,
    required this.symbol,
    required this.hide,
    required this.textColor,
    required this.mutedColor,
    required this.gridColor,
  });

  final List<_WaterfallStep> steps;
  final String symbol;
  final bool hide;
  final Color textColor;
  final Color mutedColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;

    const topPad = 24.0;
    const bottomPad = 26.0;
    final plotHeight = math.max(40.0, size.height - topPad - bottomPad);

    var minVal = 0.0;
    var maxVal = 0.0;
    for (final s in steps) {
      minVal = math.min(minVal, math.min(s.start, s.end));
      maxVal = math.max(maxVal, math.max(s.start, s.end));
    }
    if (maxVal == minVal) maxVal = minVal + 100;
    final range = maxVal - minVal;

    double yFor(double v) => topPad + ((maxVal - v) / range) * plotHeight;

    final zeroY = yFor(0);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1.1,
    );

    final slotWidth = size.width / steps.length;
    final barWidth = math.min(54.0, math.max(22.0, slotWidth * 0.52));

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final centerX = i * slotWidth + slotWidth / 2;
      final left = centerX - barWidth / 2;
      final y1 = yFor(step.start);
      final y2 = yFor(step.end);
      final top = math.min(y1, y2);
      final height = math.max(5.0, (y1 - y2).abs());

      // Connector line to previous step
      if (i > 0 && !step.isTotal) {
        final prevRight = (i - 1) * slotWidth + slotWidth / 2 + barWidth / 2;
        _drawDashedLine(
          canvas,
          Offset(prevRight + 2, y1),
          Offset(left - 2, y1),
          gridColor,
        );
      } else if (i > 0 && step.isTotal) {
        final prevRight = (i - 1) * slotWidth + slotWidth / 2 + barWidth / 2;
        _drawDashedLine(
          canvas,
          Offset(prevRight + 2, y2),
          Offset(left - 2, y2),
          gridColor,
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          const Radius.circular(6),
        ),
        Paint()..color = step.color,
      );

      // Value label above bar
      final valLabel = hide
          ? '$symbol••'
          : _compactMoney(step.delta, symbol, showSign: !step.isTotal);
      final valPainter = TextPainter(
        text: TextSpan(
          text: valLabel,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: step.isTotal ? textColor : mutedColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: slotWidth + 6);
      valPainter.paint(
        canvas,
        Offset(centerX - valPainter.width / 2, math.max(2, top - 16)),
      );

      // Category label at bottom
      final shortLabel = step.label.length > 10
          ? '${step.label.substring(0, 9)}…'
          : step.label;
      final lblPainter = TextPainter(
        text: TextSpan(
          text: shortLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: step.isTotal ? FontWeight.w700 : FontWeight.w500,
            color: step.isTotal ? textColor : mutedColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: slotWidth - 2);
      lblPainter.paint(
        canvas,
        Offset(centerX - lblPainter.width / 2, size.height - 19),
      );
    }
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = start.dx;
    while (x < end.dx) {
      final nextX = math.min(x + 3.5, end.dx);
      canvas.drawLine(Offset(x, start.dy), Offset(nextX, start.dy), paint);
      x += 6.5;
    }
  }

  static String _compactMoney(
    double v,
    String symbol, {
    required bool showSign,
  }) {
    final abs = v.abs();
    final str = abs >= 1000
        ? '${(abs / 1000).toStringAsFixed(1)}k'
        : abs.toStringAsFixed(abs == abs.roundToDouble() ? 0 : 0);
    if (v < 0) return '-$symbol$str';
    if (showSign && v > 0) return '+$symbol$str';
    return '$symbol$str';
  }

  @override
  bool shouldRepaint(_WaterfallPainter oldDelegate) =>
      oldDelegate.steps != steps || oldDelegate.hide != hide;
}

/// Daily rounded bar chart.
class FinanceDailyChart extends StatelessWidget {
  const FinanceDailyChart({
    super.key,
    required this.values,
    required this.accent,
    required this.muted,
    required this.gridColor,
    required this.symbol,
    required this.hide,
  });

  final List<double> values;
  final Color accent;
  final Color muted;
  final Color gridColor;
  final String symbol;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final maxVal = values.fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                maxVal > 0
                    ? 'Pico diario: ${FinanceFormat.money(maxVal, symbol: symbol, hide: hide)}'
                    : 'Sin gastos diarios aún',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '1 – ${values.length}',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: CustomPaint(
            painter: _BarsPainter(
              values: values,
              maxVal: maxVal,
              barColor: accent,
              emptyColor: gridColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.values,
    required this.maxVal,
    required this.barColor,
    required this.emptyColor,
  });

  final List<double> values;
  final double maxVal;
  final Color barColor;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final gridPaint = Paint()
      ..color = emptyColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );

    final count = values.length;
    final slotWidth = size.width / count;
    final barWidth = math.max(3.0, slotWidth * 0.62);
    final barPaint = Paint()..color = barColor;
    final zeroPaint = Paint()..color = emptyColor.withValues(alpha: 0.7);

    for (var i = 0; i < count; i++) {
      final v = values[i];
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      if (v <= 0 || maxVal <= 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - 4, barWidth, 3),
            const Radius.circular(1.5),
          ),
          zeroPaint,
        );
      } else {
        final h = math.max(6.0, (v / maxVal) * (size.height - 8));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - h - 1, barWidth, h),
            const Radius.circular(3.5),
          ),
          barPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maxVal != maxVal ||
      oldDelegate.barColor != barColor;
}
