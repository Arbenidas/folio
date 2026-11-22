import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// Un mismo ritmo para las transiciones; respeta «Reducir movimiento».
abstract final class EditorMotion {
  static const curve = Curves.easeOutCubic;
  static const emphasizedCurve = Curves.easeOutQuart;
  static const reverseCurve = Curves.easeInCubic;

  static Duration duration(BuildContext context, [int milliseconds = 190]) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);

  static AnimationStyle dialog(BuildContext context) => AnimationStyle(
    duration: duration(context, 190),
    reverseDuration: duration(context, 140),
    curve: curve,
    reverseCurve: reverseCurve,
  );
}

class AnimatedNotesPanel extends StatelessWidget {
  const AnimatedNotesPanel({
    super.key,
    required this.visible,
    required this.child,
    this.width = defaultWidth,
    this.onResizeDelta,
  });

  static const double defaultWidth = 272;

  final bool visible;
  final Widget child;
  final double width;
  final ValueChanged<double>? onResizeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: visible ? 1 : 0),
            duration: EditorMotion.duration(context, 240),
            curve: EditorMotion.emphasizedCurve,
            // El contenido conserva su ancho y su estado mientras se oculta.
            child: RepaintBoundary(
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(child: child),
                    if (onResizeDelta != null)
                      _PanelResizeHandle(
                        color: style.isGraphic
                            ? style.ink
                            : colors.outlineVariant,
                        accentColor: colors.primary,
                        baseWidth: style.isGraphic ? style.lineWidth : 1,
                        invertDelta: false,
                        onDelta: onResizeDelta!,
                      )
                    else
                      VerticalDivider(
                        width: style.isGraphic ? style.lineWidth : 1,
                        thickness: style.isGraphic ? style.lineWidth : 1,
                        color: style.isGraphic ? style.ink : null,
                      ),
                  ],
                ),
              ),
            ),
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: value,
                child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedRightPanel extends StatelessWidget {
  const AnimatedRightPanel({
    super.key,
    required this.visible,
    required this.width,
    required this.child,
    this.onResizeDelta,
  });

  final bool visible;
  final double width;
  final Widget child;
  final ValueChanged<double>? onResizeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          // IMPORTANTE: TweenAnimationBuilder debe quedar FUERA de TickerMode
          // para poder animar de 1 -> 0 al cerrar el panel sin congelarse.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: visible ? 1 : 0),
            duration: EditorMotion.duration(context, 240),
            curve: EditorMotion.emphasizedCurve,
            child: TickerMode(
              enabled: visible,
              child: RepaintBoundary(
                child: SizedBox(
                  width: width,
                  child: Row(
                    children: [
                      if (onResizeDelta != null)
                        _PanelResizeHandle(
                          color: style.isGraphic
                              ? style.ink
                              : colors.outlineVariant,
                          accentColor: colors.primary,
                          baseWidth: style.isGraphic ? style.lineWidth : 1,
                          onDelta: onResizeDelta!,
                        )
                      else
                        VerticalDivider(
                          width: style.isGraphic ? style.lineWidth : 1,
                          thickness: style.isGraphic ? style.lineWidth : 1,
                          color: style.isGraphic ? style.ink : null,
                        ),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
            builder: (context, value, child) {
              if (!visible && value == 0) return const SizedBox.shrink();
              return ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PanelResizeHandle extends StatefulWidget {
  const _PanelResizeHandle({
    required this.color,
    required this.accentColor,
    required this.onDelta,
    this.baseWidth = 1,
    this.invertDelta = true,
  });

  final Color color;
  final Color accentColor;
  final ValueChanged<double> onDelta;
  final double baseWidth;
  final bool invertDelta;

  @override
  State<_PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<_PanelResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (details) => widget.onDelta(
          widget.invertDelta ? -details.delta.dx : details.delta.dx,
        ),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: EditorMotion.duration(context, 140),
              width: active ? 2.5 : widget.baseWidth,
              color: active
                  ? widget.accentColor.withValues(alpha: 0.72)
                  : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class FadingLabel extends StatelessWidget {
  const FadingLabel(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: EditorMotion.duration(context, 150),
    switchInCurve: EditorMotion.curve,
    switchOutCurve: EditorMotion.reverseCurve,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.centerLeft,
      children: [...previous, ?current],
    ),
    child: Text(
      text,
      key: ValueKey(text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}
