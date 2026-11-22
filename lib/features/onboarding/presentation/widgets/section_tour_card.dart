import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../finance/domain/finance_models.dart';

class SectionTourStep {
  const SectionTourStep({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
    this.padding = const EdgeInsets.all(6),
    this.borderRadius = 14,
  });

  final String badge;
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;
  final EdgeInsets padding;
  final double borderRadius;
}

/// Interactive spotlight coachmark overlay that dims the background, punches a
/// true illuminated cutout with a glowing border around [SectionTourStep.targetKey],
/// and positions the explanation card smartly right next to the target element.
class SpotlightTourOverlay extends StatefulWidget {
  const SpotlightTourOverlay({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final List<SectionTourStep> steps;
  final int currentIndex;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  State<SpotlightTourOverlay> createState() => _SpotlightTourOverlayState();
}

class _SpotlightTourOverlayState extends State<SpotlightTourOverlay> {
  final GlobalKey _overlayKey = GlobalKey();
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant SpotlightTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.steps != widget.steps) {
      _scheduleMeasure();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureTarget();
      // Second pass catches any late LayoutBuilder / scroll / tab transitions.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureTarget();
      });
    });
  }

  void _measureTarget() {
    final step =
        widget.steps[widget.currentIndex.clamp(0, widget.steps.length - 1)];
    final key = step.targetKey;
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (key == null || overlayBox == null || !overlayBox.hasSize) {
      if (_targetRect != null) setState(() => _targetRect = null);
      return;
    }
    final targetCtx = key.currentContext;
    if (targetCtx == null) {
      if (_targetRect != null) setState(() => _targetRect = null);
      return;
    }
    final targetBox = targetCtx.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize || !targetBox.attached) {
      if (_targetRect != null) setState(() => _targetRect = null);
      return;
    }

    // Ensure the target is scrolled into view if it lives in a scrollable!
    try {
      Scrollable.ensureVisible(
        targetCtx,
        alignment: 0.25,
        duration: const Duration(milliseconds: 180),
      );
    } catch (_) {}

    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final raw = topLeft & targetBox.size;
    final padded = Rect.fromLTRB(
      math.max(4, raw.left - step.padding.left),
      math.max(4, raw.top - step.padding.top),
      math.min(overlayBox.size.width - 4, raw.right + step.padding.right),
      math.min(overlayBox.size.height - 4, raw.bottom + step.padding.bottom),
    );
    if (padded.width <= 0 || padded.height <= 0) {
      if (_targetRect != null) setState(() => _targetRect = null);
      return;
    }
    if (_targetRect != padded) {
      setState(() => _targetRect = padded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FinancePalette.of(context);
    final step =
        widget.steps[widget.currentIndex.clamp(0, widget.steps.length - 1)];

    return LayoutBuilder(
      key: _overlayKey,
      builder: (context, constraints) {
        final size = constraints.biggest;
        final rect = _targetRect;
        final cardWidth = math.min(368.0, math.max(260.0, size.width - 28.0));
        final placement = _computeCardOffset(size, rect, cardWidth);

        return Stack(
          children: [
            // Dimmed backdrop with true spotlight hole + glowing highlight ring
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Trap taps outside card so accidental clicks don't break tour
                child: rect == null
                    ? CustomPaint(
                        size: size,
                        painter: _SpotlightBackdropPainter(
                          hole: null,
                          borderRadius: step.borderRadius,
                          ringColor: palette.accent,
                          scrimColor: Colors.black.withValues(
                            alpha: palette.isDark ? 0.68 : 0.56,
                          ),
                        ),
                      )
                    : TweenAnimationBuilder<Rect?>(
                        tween: RectTween(begin: rect, end: rect),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        builder: (context, animRect, _) => CustomPaint(
                          size: size,
                          painter: _SpotlightBackdropPainter(
                            hole: animRect,
                            borderRadius: step.borderRadius,
                            ringColor: palette.accent,
                            scrimColor: Colors.black.withValues(
                              alpha: palette.isDark ? 0.68 : 0.56,
                            ),
                          ),
                        ),
                      ),
              ),
            ),

            // Smartly positioned Coach Card right beside the highlighted element
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: placement.dx,
              top: placement.dy,
              width: cardWidth,
              child: FloatingSectionTourCard(
                steps: widget.steps,
                currentIndex: widget.currentIndex,
                onNext: widget.onNext,
                onBack: widget.onBack,
                onSkip: widget.onSkip,
              ),
            ),
          ],
        );
      },
    );
  }

  Offset _computeCardOffset(Size screen, Rect? target, double cardW) {
    const estCardH = 216.0;
    const gap = 14.0;
    const margin = 14.0;

    if (target == null) {
      return Offset(
        (screen.width - cardW) / 2,
        math.max(margin, screen.height - estCardH - 24),
      );
    }

    // 1. Prefer right side if target is a sidebar/rail item and space fits
    final spaceRight = screen.width - target.right - margin;
    if (target.width < 320 && spaceRight >= cardW + gap) {
      final top = (target.center.dy - estCardH / 2)
          .clamp(margin, math.max(margin, screen.height - estCardH - margin))
          .toDouble();
      return Offset(target.right + gap, top);
    }

    // 2. Prefer left side if target is on the right edge (e.g., floating FAB)
    final spaceLeft = target.left - margin;
    if (target.width < 320 && spaceLeft >= cardW + gap) {
      final top = (target.center.dy - estCardH / 2)
          .clamp(margin, math.max(margin, screen.height - estCardH - margin))
          .toDouble();
      return Offset(target.left - cardW - gap, top);
    }

    final centeredX = (target.center.dx - cardW / 2)
        .clamp(margin, math.max(margin, screen.width - cardW - margin))
        .toDouble();

    // 3. Prefer below target
    final spaceBelow = screen.height - target.bottom - margin;
    if (spaceBelow >= estCardH + gap) {
      return Offset(centeredX, target.bottom + gap);
    }

    // 4. Else above target
    final spaceAbove = target.top - margin;
    if (spaceAbove >= estCardH + gap) {
      return Offset(centeredX, target.top - estCardH - gap);
    }

    // 5. Fallback: bottom-center safely inside screen
    return Offset(
      centeredX,
      math.max(margin, screen.height - estCardH - margin),
    );
  }
}

class _SpotlightBackdropPainter extends CustomPainter {
  const _SpotlightBackdropPainter({
    required this.hole,
    required this.borderRadius,
    required this.ringColor,
    required this.scrimColor,
  });

  final Rect? hole;
  final double borderRadius;
  final Color ringColor;
  final Color scrimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final path = Path()..addRect(fullRect);

    if (hole != null) {
      final rrect = RRect.fromRectAndRadius(
        hole!,
        Radius.circular(borderRadius),
      );
      path
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(path, Paint()..color = scrimColor);

      // Soft outer glow halo around the spotlighted widget
      canvas.drawRRect(
        rrect.inflate(2.5),
        Paint()
          ..color = ringColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      // Crisp bright spotlight border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    } else {
      canvas.drawPath(path, Paint()..color = scrimColor);
    }
  }

  @override
  bool shouldRepaint(_SpotlightBackdropPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.scrimColor != scrimColor;
}

/// Sleek coach card used inside [SpotlightTourOverlay].
class FloatingSectionTourCard extends StatelessWidget {
  const FloatingSectionTourCard({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final List<SectionTourStep> steps;
  final int currentIndex;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final step = steps[currentIndex.clamp(0, steps.length - 1)];
    final isFirst = currentIndex <= 0;
    final isLast = currentIndex >= steps.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.48 : 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(step.icon, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${step.badge} · ${currentIndex + 1} de ${steps.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w800,
                        color: palette.accent,
                      ),
                    ),
                    Text(
                      step.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(4),
                minimumSize: Size.zero,
                onPressed: onSkip,
                child: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.description,
            style: TextStyle(
              fontSize: 12.8,
              height: 1.45,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(right: 5),
                      width: i == currentIndex ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == currentIndex
                            ? palette.accent
                            : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isFirst)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      onPressed: onSkip,
                      child: Text(
                        'Omitir',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      onPressed: onBack,
                      child: Text(
                        'Atrás',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    minimumSize: Size.zero,
                    borderRadius: BorderRadius.circular(9),
                    onPressed: onNext,
                    child: Text(
                      isLast ? '¡Entendido!' : 'Siguiente',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
