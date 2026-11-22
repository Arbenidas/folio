import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ColorScheme, Material, TextTheme, Theme, Tooltip;

import '../../../core/theme.dart';
import '../../editor/presentation/widgets/editor_motion.dart';
import 'pomodoro_controller.dart';

/// Compact Pomodoro capsule for the top toolbar with a clean anchored popover.
class PomodoroControl extends StatefulWidget {
  const PomodoroControl({super.key, required this.controller});

  final PomodoroController controller;

  @override
  State<PomodoroControl> createState() => _PomodoroControlState();
}

class _PomodoroControlState extends State<PomodoroControl> {
  final _overlayController = OverlayPortalController();
  final _layerLink = LayerLink();
  bool _hovered = false;

  void _togglePopover() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
    }
    setState(() {});
  }

  void _hidePopover() {
    if (!_overlayController.isShowing) return;
    _overlayController.hide();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final style = FolioStyle.of(context);
        final running = widget.controller.isRunning;
        final showing = _overlayController.isShowing;
        final fg = running
            ? colors.onPrimaryContainer
            : style.isPop
            ? style.onAccent
            : colors.onSurface;

        return OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (overlayContext) {
            final theme = Theme.of(context);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hidePopover,
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.topRight,
                  offset: const Offset(0, 8),
                  child: _PomodoroPopover(
                    controller: widget.controller,
                    colors: theme.colorScheme,
                    textTheme: theme.textTheme,
                    style: FolioStyle.of(context),
                    onClose: _hidePopover,
                  ),
                ),
              ],
            );
          },
          child: CompositedTransformTarget(
            link: _layerLink,
            child: Tooltip(
              message: running
                  ? 'Pomodoro en curso (${widget.controller.phaseLabel})'
                  : 'Temporizador Pomodoro',
              child: Semantics(
                label: 'Pomodoro, ${widget.controller.display}. Ampliar controles',
                button: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: CupertinoButton(
                    key: const ValueKey('pomodoro-compact'),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _togglePopover,
                    child: AnimatedContainer(
                      duration: EditorMotion.duration(context, 150),
                      curve: EditorMotion.curve,
                      height: 27,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: running
                            ? colors.primaryContainer.withValues(alpha: 0.85)
                            : showing || _hovered
                            ? colors.surfaceContainerHigh
                            : colors.surfaceContainerLow.withValues(
                                alpha: style.isPop ? 0.25 : 0.9,
                              ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: running
                              ? colors.primary.withValues(alpha: 0.55)
                              : style.isGraphic
                              ? style.ink.withValues(alpha: 0.7)
                              : colors.outlineVariant,
                          width: style.isGraphic ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: EditorMotion.duration(context, 180),
                            width: 6.5,
                            height: 6.5,
                            decoration: BoxDecoration(
                              color: running
                                  ? colors.primary
                                  : colors.onSurfaceVariant.withValues(
                                      alpha: 0.55,
                                    ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.controller.display,
                            style: TextStyle(
                              color: fg,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Menlo',
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _PomodoroPopover extends StatelessWidget {
  const _PomodoroPopover({
    required this.controller,
    required this.colors,
    required this.textTheme,
    required this.style,
    required this.onClose,
  });

  final PomodoroController controller;
  final ColorScheme colors;
  final TextTheme textTheme;
  final FolioStyle style;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: EditorMotion.duration(context, 160),
      curve: EditorMotion.emphasizedCurve,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.topRight,
        child: Opacity(
          opacity: ((scale - 0.94) / 0.06).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: Material(
        key: const ValueKey('pomodoro-expanded'),
        color: colors.surfaceContainerLow,
        elevation: 12,
        shadowColor: colors.shadow.withValues(alpha: 0.24),
        shape: style.isGraphic
            ? style.outline
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 264,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: controller.isRunning
                            ? colors.primaryContainer
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.timer,
                            size: 13,
                            color: controller.isRunning
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            controller.phaseLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: controller.isRunning
                                  ? colors.onPrimaryContainer
                                  : colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(26, 26),
                      onPressed: onClose,
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      controller.display,
                      style: textTheme.headlineMedium?.copyWith(
                        fontSize: 32,
                        fontFamily: 'Menlo',
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        borderRadius: BorderRadius.circular(9),
                        onPressed: controller.toggle,
                        child: Text(
                          controller.isRunning ? 'Pausar' : 'Iniciar',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Reiniciar temporizador',
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: controller.reset,
                        child: Icon(
                          CupertinoIcons.restart,
                          size: 16,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Column(
                    children: [
                      _durationSlider(
                        label: 'Enfoque',
                        value: controller.focusMinutes,
                        maximum: 90,
                        onChanged: (minutes) =>
                            controller.configure(focus: minutes),
                      ),
                      _durationSlider(
                        label: 'Descanso',
                        value: controller.breakMinutes,
                        maximum: 30,
                        onChanged: (minutes) =>
                            controller.configure(rest: minutes),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _durationSlider({
    required String label,
    required int value,
    required int maximum,
    required ValueChanged<int> onChanged,
  }) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(
          label,
          style: TextStyle(fontSize: 11.5, color: colors.onSurface),
        ),
      ),
      Expanded(
        child: CupertinoSlider(
          min: 1,
          max: maximum.toDouble(),
          divisions: maximum - 1,
          value: value.toDouble(),
          onChanged: (minutes) => onChanged(minutes.round()),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(
          '$value min',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}
