import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import 'editor_motion.dart';
import '../controllers/vim_controller.dart';

class EditorPane extends StatelessWidget {
  const EditorPane({
    super.key,
    required this.vim,
    required this.focusNode,
    required this.editableKey,
    required this.previewVisible,
    required this.onTogglePreview,
  });
  final VimController vim;
  final FocusNode focusNode;
  final GlobalKey<EditableTextState> editableKey;
  final bool previewVisible;
  final VoidCallback onTogglePreview;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      children: [
        EditorPanelHeader(
          title: 'EDITOR',
          trailing: Tooltip(
            message: previewVisible
                ? 'Ocultar vista previa'
                : 'Mostrar vista previa',
            child: CupertinoButton(
              padding: const EdgeInsets.all(7),
              minimumSize: Size.zero,
              onPressed: onTogglePreview,
              child: Icon(
                previewVisible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Stack(
              children: [
                if (vim.text.text.isEmpty)
                  IgnorePointer(
                    child: Text(
                      'Escribe tus apuntes aquí…',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'Georgia',
                        fontSize: 14,
                      ),
                    ),
                  ),
                EditableText(
                  key: editableKey,
                  controller: vim.text,
                  focusNode: focusNode,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 15,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  cursorColor: Theme.of(context).colorScheme.primary,
                  backgroundCursorColor: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                  maxLines: null,
                  expands: true,
                  readOnly: vim.enabled && !vim.insert,
                  showCursor: true,
                  cursorWidth: vim.enabled && !vim.insert ? 7 : 2,
                  selectionColor: Theme.of(context).colorScheme.primary
                      .withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.42
                            : 0.24,
                      ),
                  selectionControls: desktopTextSelectionControls,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ],
            ),
          ),
        ),
        _EditorStatusBar(vim: vim),
      ],
    ),
  );
}

class _EditorStatusBar extends StatefulWidget {
  const _EditorStatusBar({required this.vim});

  final VimController vim;

  @override
  State<_EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<_EditorStatusBar> {
  late int _observedRevision;

  @override
  void initState() {
    super.initState();
    _observedRevision = widget.vim.keyPressRevision.value;
    widget.vim.keyPressRevision.addListener(_onKeyActivity);
  }

  @override
  void didUpdateWidget(covariant _EditorStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vim == widget.vim) return;
    oldWidget.vim.keyPressRevision.removeListener(_onKeyActivity);
    _observedRevision = widget.vim.keyPressRevision.value;
    widget.vim.keyPressRevision.addListener(_onKeyActivity);
  }

  void _onKeyActivity() {
    final revision = widget.vim.keyPressRevision.value;
    if (revision == _observedRevision) return;
    _observedRevision = revision;
    setState(() {});
  }

  @override
  void dispose() {
    widget.vim.keyPressRevision.removeListener(_onKeyActivity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vim = widget.vim;
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(
            vim.mode,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: vim.insert ? colors.primary : colors.secondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vim.message ??
                  (vim.enabled
                      ? (vim.insert ? 'Esc: navegar' : 'i: escribir · ?: ayuda')
                      : 'Edición normal'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ),
          Text(
            vim.position,
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
          if (vim.lastKeys.isNotEmpty) ...[
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: EditorMotion.duration(context, 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(vim.lastKeys.join('\u0000')),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < vim.lastKeys.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          '+',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    _LastKeyCap(
                      label: vim.lastKeys[index],
                      style: style,
                      colors: colors,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LastKeyCap extends StatelessWidget {
  const _LastKeyCap({
    required this.label,
    required this.style,
    required this.colors,
  });

  final String label;
  final FolioStyle style;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 24, minHeight: 21),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: style.isGraphic ? style.accent : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(style.isRetro ? 4 : 6),
      border: Border.all(
        color: style.isGraphic ? style.ink : colors.outlineVariant,
        width: style.isGraphic ? style.lineWidth : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: style.isGraphic ? style.shadow : colors.shadow,
          offset: Offset(0, style.isGraphic ? 2 : 1),
        ),
      ],
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: style.isGraphic ? style.onAccent : colors.onSurface,
      ),
    ),
  );
}

class EditorPanelHeader extends StatelessWidget {
  const EditorPanelHeader({
    super.key,
    required this.title,
    this.trailing,
    this.preview = false,
  });

  final String title;
  final Widget? trailing;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: style.isGraphic
          ? BoxDecoration(
              color: style.isPop && preview
                  ? colors.surfaceContainerHighest
                  : colors.surface,
              border: Border(bottom: BorderSide(color: style.ink)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurfaceVariant,
                fontFamily: style.isRetro ? 'Menlo' : null,
                fontWeight: style.isGraphic ? FontWeight.w700 : null,
                letterSpacing: 1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
