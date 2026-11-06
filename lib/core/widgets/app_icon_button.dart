import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// Icon button with consistent contrast for hover, press, and disabled states.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.padding = const EdgeInsets.all(6),
    this.size = 18,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double size;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: MacosIconButton(
        padding: widget.padding,
        semanticLabel: widget.semanticLabel,
        pressedOpacity: 1,
        hoverColor: colors.surfaceContainerHighest,
        icon: MacosIcon(
          widget.icon,
          size: widget.size,
          color: !enabled
              ? colors.onSurfaceVariant.withValues(alpha: 0.55)
              : _hovered
              ? colors.primary
              : colors.onSurface,
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}
