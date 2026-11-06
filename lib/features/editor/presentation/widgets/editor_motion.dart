import 'package:flutter/material.dart';

/// Un mismo ritmo para las transiciones; respeta «Reducir movimiento».
abstract final class EditorMotion {
  static const curve = Curves.easeInOutCubic;

  static Duration duration(BuildContext context, [int milliseconds = 180]) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);

  static AnimationStyle dialog(BuildContext context) => AnimationStyle(
    duration: duration(context),
    reverseDuration: duration(context, 140),
    curve: curve,
    reverseCurve: Curves.easeInCubic,
  );
}

class AnimatedNotesPanel extends StatelessWidget {
  const AnimatedNotesPanel({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !visible,
    child: IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: visible ? 1 : 0),
          duration: EditorMotion.duration(context, 260),
          curve: EditorMotion.curve,
          // El contenido conserva su ancho y su estado mientras se oculta.
          child: SizedBox(
            width: 236,
            child: Row(
              children: [
                Expanded(child: child),
                const VerticalDivider(width: 1, thickness: 1),
              ],
            ),
          ),
          builder: (context, value, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class FadingLabel extends StatelessWidget {
  const FadingLabel(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: EditorMotion.duration(context, 140),
    switchInCurve: EditorMotion.curve,
    switchOutCurve: Curves.easeInCubic,
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
