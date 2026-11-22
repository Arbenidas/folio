import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../theme.dart';

/// Icon button with smooth hover, active, press, and disabled states.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.padding = const EdgeInsets.all(6),
    this.size = 18,
    this.active = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double size;
  final bool active;
  final int badgeCount;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final enabled = widget.onPressed != null;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 140);

    final iconColor = !enabled
        ? colors.onSurfaceVariant.withValues(alpha: 0.48)
        : widget.active
        ? colors.primary
        : _hovered
        ? colors.primary
        : colors.onSurface;

    Widget icon = MacosIcon(widget.icon, size: widget.size, color: iconColor);
    if (widget.badgeCount > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -6,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onPointerCancel: enabled
            ? (_) => setState(() => _pressed = false)
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: !style.isGraphic
                ? BoxDecoration(
                    color: widget.active
                        ? colors.secondaryContainer
                        : _hovered && enabled
                        ? colors.surfaceContainerHighest.withValues(alpha: 0.72)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: MacosIconButton(
              padding: widget.padding,
              semanticLabel: widget.semanticLabel,
              pressedOpacity: 0.85,
              backgroundColor: Colors.transparent,
              hoverColor: Colors.transparent,
              icon: icon,
              onPressed: widget.onPressed,
            ),
          ),
        ),
      ),
    );
    if (!style.isGraphic || widget.size < 18) return button;
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 3),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: style.panel(
          widget.active || _hovered
              ? style.accent
              : colors.surfaceContainerLowest,
          lift: enabled ? (style.isPop ? 3 : 2) : 0,
        ),
        child: button,
      ),
    );
  }
}
