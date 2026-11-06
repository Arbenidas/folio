import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
        SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EDITOR',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Tooltip(
                  message: previewVisible
                      ? 'Ocultar vista previa'
                      : 'Mostrar vista previa',
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(7),
                    minimumSize: Size.zero,
                    onPressed: onTogglePreview,
                    child: Icon(
                      previewVisible
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      size: 17,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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
                  backgroundCursorColor: Colors.grey,
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
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                vim.mode,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: vim.insert
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  vim.message ??
                      (vim.enabled
                          ? (vim.insert
                                ? 'Esc: navegar'
                                : 'i: escribir · ?: ayuda')
                          : 'Edición normal'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                vim.position,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (vim.lastKey case final key?) ...[
                const SizedBox(width: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
