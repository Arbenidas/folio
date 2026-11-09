import 'package:flutter/material.dart';

import 'editor_motion.dart';

Offset editorMenuAnchor(BuildContext context) {
  final button = context.findRenderObject()! as RenderBox;
  return button.localToGlobal(button.size.bottomLeft(Offset.zero));
}

Future<T?> showEditorActionMenu<T>(
  BuildContext context,
  Offset anchor,
  List<PopupMenuEntry<T>> items,
) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final position = overlay.globalToLocal(anchor);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromSize(position & Size.zero, overlay.size),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
    popUpAnimationStyle: EditorMotion.dialog(context),
    items: items,
  );
}

PopupMenuItem<T> editorActionItem<T>(
  T value,
  IconData icon,
  String label, {
  Color? color,
}) => PopupMenuItem<T>(
  value: value,
  height: 36,
  child: Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 9),
      Flexible(
        child: Text(label, style: TextStyle(color: color)),
      ),
    ],
  ),
);
