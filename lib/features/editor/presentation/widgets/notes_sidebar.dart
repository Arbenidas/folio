import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show Colors, Material, Scrollbar, ScrollbarTheme, ScrollbarThemeData, Theme;
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/theme.dart';
import '../../domain/markdown_document.dart';
import 'editor_action_menu.dart';
import 'editor_motion.dart';

class SidebarDragData {
  const SidebarDragData.note(this.value) : isFolder = false;
  const SidebarDragData.folder(this.value) : isFolder = true;

  final String value;
  final bool isFolder;
}

enum _NoteAction { rename, delete }

enum _FolderAction { newNote, newSubfolder, rename, delete }

class NotesSidebar extends StatelessWidget {
  const NotesSidebar({
    super.key,
    required this.notes,
    required this.folderPaths,
    required this.selectedId,
    required this.collapsedFolders,
    required this.dropFolder,
    required this.focusNode,
    required this.scrollController,
    required this.onKeyEvent,
    required this.onNewFolder,
    required this.onNewNote,
    required this.onNewSubfolder,
    required this.onNewNoteInFolder,
    required this.onRenameFolder,
    required this.onRenameNote,
    required this.onDeleteFolder,
    required this.onDeleteNote,
    required this.onSelectNote,
    required this.onToggleFolder,
    required this.canDropIntoFolder,
    required this.onDropIntoFolder,
  });

  final List<MarkdownDocument> notes;
  final Set<String> folderPaths;
  final String? selectedId;
  final Set<String> collapsedFolders;
  final String? dropFolder;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final FocusOnKeyEventCallback onKeyEvent;
  final VoidCallback onNewFolder;
  final VoidCallback onNewNote;
  final ValueChanged<String> onNewSubfolder;
  final ValueChanged<String> onNewNoteInFolder;
  final ValueChanged<String> onRenameFolder;
  final ValueChanged<MarkdownDocument> onRenameNote;
  final ValueChanged<String> onDeleteFolder;
  final ValueChanged<MarkdownDocument> onDeleteNote;
  final ValueChanged<MarkdownDocument> onSelectNote;
  final ValueChanged<String> onToggleFolder;
  final bool Function(SidebarDragData, String) canDropIntoFolder;
  final void Function(SidebarDragData, String) onDropIntoFolder;

  String? _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? null : path.substring(0, slash);
  }

  String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final tree = ListView(
      controller: scrollController,
      padding: switch (style.kind) {
        AppStyle.retro => const EdgeInsets.fromLTRB(9, 8, 14, 16),
        AppStyle.pop => const EdgeInsets.fromLTRB(10, 12, 14, 16),
        AppStyle.clasico => const EdgeInsets.fromLTRB(6, 4, 6, 16),
      },
      children: _childrenOf(context, null, 0),
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: style.isGraphic
            ? Border(
                right: BorderSide(color: style.ink, width: style.lineWidth),
              )
            : null,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 5, 10, 5),
            decoration: style.isGraphic
                ? BoxDecoration(
                    color: style.isPop ? style.folderAccent(3) : colors.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: style.ink,
                        width: style.lineWidth,
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'NOTAS',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: style.isRetro ? 'Menlo' : null,
                      color: style.isPop
                          ? style.folderForeground(3)
                          : colors.onSurfaceVariant,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _SidebarAction(
                  icon: CupertinoIcons.folder_badge_plus,
                  tooltip: 'Nueva carpeta',
                  onPressed: onNewFolder,
                ),
                const SizedBox(width: 4),
                _SidebarAction(
                  icon: CupertinoIcons.add,
                  tooltip: 'Nueva nota (⌘N)',
                  onPressed: onNewNote,
                ),
              ],
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: focusNode,
              onKeyEvent: onKeyEvent,
              child: style.isRetro
                  ? ScrollbarTheme(
                      data: ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll(style.ink),
                        trackColor: WidgetStatePropertyAll(
                          colors.surfaceContainerHighest,
                        ),
                        trackBorderColor: WidgetStatePropertyAll(style.ink),
                      ),
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 8,
                        radius: Radius.zero,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: tree,
                        ),
                      ),
                    )
                  : tree,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _childrenOf(BuildContext context, String? parent, int depth) {
    final style = FolioStyle.of(context);
    final folders =
        folderPaths.where((path) => _parentOf(path) == parent).toList()..sort(
          (a, b) =>
              _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase()),
        );
    final rows = [
      for (final folder in folders) _folderRow(context, folder, depth),
      for (final note in notes.where((note) => note.folder == parent))
        _noteRow(context, note, parent == null ? 0 : depth - 1),
    ];
    // Cap the indentation to leave room for labels in very deep trees.
    if (!style.isRetro || parent == null || depth > 6) return rows;
    return [
      for (final (index, row) in rows.indexed)
        CustomPaint(
          key: row.key,
          painter: _TreeBranch(
            ink: style.ink,
            isLast: index == rows.length - 1,
            isFolder: index < folders.length,
          ),
          child: Padding(padding: const EdgeInsets.only(left: 19), child: row),
        ),
    ];
  }

  Widget _folderRow(BuildContext context, String path, int depth) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final tabIndex = path.codeUnits.fold<int>(0, (sum, code) => sum + code);
    final tab = style.folderAccent(tabIndex);
    final expanded = !collapsedFolders.contains(path);
    return Draggable<SidebarDragData>(
      key: ValueKey(('folder', path)),
      data: SidebarDragData.folder(path),
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.folder, size: 17),
                const SizedBox(width: 8),
                Text(_nameOf(path)),
              ],
            ),
          ),
        ),
      ),
      child: DragTarget<SidebarDragData>(
        onWillAcceptWithDetails: (details) =>
            canDropIntoFolder(details.data, path),
        onAcceptWithDetails: (details) => onDropIntoFolder(details.data, path),
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty;
          final justDropped = dropFolder == path;
          final foreground = hovering
              ? colors.onTertiaryContainer
              : justDropped
              ? colors.onSecondaryContainer
              : colors.onSurface;
          return Padding(
            padding: EdgeInsets.only(left: style.isRetro ? 0 : depth * 14),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: EditorMotion.duration(context, 170),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(vertical: style.isPop ? 5 : 2),
                  decoration: style.isPop
                      ? style.panel(
                          hovering ? colors.tertiaryContainer : colors.surface,
                          lift: 3,
                        )
                      : BoxDecoration(
                          color: hovering
                              ? colors.tertiaryContainer
                              : justDropped
                              ? colors.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    minimumSize: Size.zero,
                    alignment: Alignment.centerLeft,
                    borderRadius: BorderRadius.circular(10),
                    pressedOpacity: 0.72,
                    onPressed: () => onToggleFolder(path),
                    child: Row(
                      children: [
                        if (style.isRetro)
                          Icon(
                            expanded
                                ? CupertinoIcons.minus_square_fill
                                : CupertinoIcons.plus_square_fill,
                            size: 13,
                            color: foreground,
                          )
                        else
                          AnimatedRotation(
                            turns: expanded ? 0 : -0.25,
                            duration: EditorMotion.duration(context, 190),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              CupertinoIcons.chevron_down,
                              size: 12,
                              color: foreground,
                            ),
                          ),
                        const SizedBox(width: 7),
                        Container(
                          padding: style.isPop ? const EdgeInsets.all(4) : null,
                          decoration: style.isPop ? style.panel(tab) : null,
                          child: AnimatedSwitcher(
                            duration: EditorMotion.duration(context, 150),
                            child: Icon(
                              hovering || justDropped
                                  ? CupertinoIcons.folder_badge_plus
                                  : expanded
                                  ? CupertinoIcons.folder_open
                                  : CupertinoIcons.folder,
                              key: ValueKey((hovering, expanded)),
                              size: 17,
                              color: style.isPop
                                  ? style.folderForeground(tabIndex)
                                  : foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _nameOf(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: foreground,
                            ),
                          ),
                        ),
                        Builder(
                          builder: (buttonContext) => AppIconButton(
                            padding: const EdgeInsets.all(4),
                            semanticLabel: 'Acciones de ${_nameOf(path)}',
                            icon: CupertinoIcons.ellipsis,
                            size: 16,
                            onPressed: () => _showFolderActions(
                              context,
                              path,
                              editorMenuAnchor(buttonContext),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: EditorMotion.duration(context, 230),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _childrenOf(context, path, depth + 1),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFolderActions(
    BuildContext context,
    String path,
    Offset globalPosition,
  ) async {
    final action = await showEditorActionMenu<_FolderAction>(
      context,
      globalPosition,
      [
        editorActionItem(
          _FolderAction.newNote,
          CupertinoIcons.doc_text,
          'Nueva nota en esta carpeta',
        ),
        editorActionItem(
          _FolderAction.newSubfolder,
          CupertinoIcons.folder_badge_plus,
          'Nueva subcarpeta',
        ),
        editorActionItem(
          _FolderAction.rename,
          CupertinoIcons.pencil,
          'Renombrar carpeta',
        ),
        editorActionItem(
          _FolderAction.delete,
          CupertinoIcons.trash,
          'Eliminar carpeta',
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _FolderAction.newNote:
        onNewNoteInFolder(path);
      case _FolderAction.newSubfolder:
        onNewSubfolder(path);
      case _FolderAction.rename:
        onRenameFolder(path);
      case _FolderAction.delete:
        onDeleteFolder(path);
      case null:
        break;
    }
  }

  Widget _noteRow(BuildContext context, MarkdownDocument note, int depth) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final selected = note.id == selectedId;
    final foreground = style.isRetro
        ? selected
              ? style.ink
              : colors.onSurfaceVariant
        : selected
        ? colors.onSecondaryContainer
        : colors.onSurface;
    return Padding(
      key: ValueKey(note.id),
      padding: EdgeInsets.only(
        left: style.isRetro || note.folder == null ? 0 : 20 + depth * 14,
      ),
      child: Draggable<SidebarDragData>(
        data: SidebarDragData.note(note.id),
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedbackOffset: const Offset(0, -10),
        feedback: Material(
          color: Colors.transparent,
          child: CupertinoPopupSurface(
            isSurfacePainted: true,
            child: SizedBox(
              width: 230,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.doc_text, size: 16),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: const SizedBox(height: 42),
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showNoteActions(context, note, details.globalPosition),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: style.isGraphic && selected
                ? style.panel(
                    style.isRetro ? colors.surface : colors.secondaryContainer,
                    lift: style.isPop ? 2 : 0,
                  )
                : BoxDecoration(
                    color: selected
                        ? colors.secondaryContainer
                        : Colors.transparent,
                    border: style.isGraphic
                        ? Border.all(
                            color: Colors.transparent,
                            width: style.lineWidth,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
            child: Row(
              children: [
                Expanded(
                  child: RawGestureDetector(
                    // Each click resolves on release, including the first of a pair.
                    gestures: {
                      SerialTapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            SerialTapGestureRecognizer
                          >(
                            () => SerialTapGestureRecognizer(
                              allowedButtonsFilter: (buttons) =>
                                  buttons == kPrimaryButton,
                            ),
                            (recognizer) =>
                                recognizer.onSerialTapUp = (details) {
                                  if (details.count > 1 && selected) {
                                    onRenameNote(note);
                                  } else {
                                    onSelectNote(note);
                                  }
                                },
                          ),
                    },
                    child: CupertinoButton(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      minimumSize: Size.zero,
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () => onSelectNote(note),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? CupertinoIcons.doc_text_fill
                                : CupertinoIcons.doc_text,
                            size: 16,
                            color: selected
                                ? foreground
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Builder(
                    builder: (buttonContext) => AppIconButton(
                      padding: const EdgeInsets.all(4),
                      semanticLabel: 'Acciones de ${note.title}',
                      icon: CupertinoIcons.ellipsis,
                      size: 15,
                      onPressed: () => _showNoteActions(
                        context,
                        note,
                        editorMenuAnchor(buttonContext),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNoteActions(
    BuildContext context,
    MarkdownDocument note,
    Offset globalPosition,
  ) async {
    final action = await showEditorActionMenu<_NoteAction>(
      context,
      globalPosition,
      [
        editorActionItem(
          _NoteAction.rename,
          CupertinoIcons.pencil,
          'Renombrar nota',
        ),
        editorActionItem(
          _NoteAction.delete,
          CupertinoIcons.trash,
          'Mover a la papelera',
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _NoteAction.rename:
        onRenameNote(note);
      case _NoteAction.delete:
        onDeleteNote(note);
      case null:
        break;
    }
  }
}

class _TreeBranch extends CustomPainter {
  const _TreeBranch({
    required this.ink,
    required this.isLast,
    required this.isFolder,
  });

  final Color ink;
  final bool isLast;
  final bool isFolder;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final join = isFolder && size.height > 40 ? 20.0 : size.height / 2;
    canvas.drawLine(
      Offset(14, 0),
      Offset(14, isLast ? join : size.height),
      pen,
    );
    canvas.drawLine(Offset(14, join), Offset(22, join), pen);
  }

  @override
  bool shouldRepaint(_TreeBranch oldDelegate) =>
      ink != oldDelegate.ink ||
      isLast != oldDelegate.isLast ||
      isFolder != oldDelegate.isFolder;
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MacosTooltip(
    message: tooltip,
    child: AppIconButton(
      semanticLabel: tooltip,
      icon: icon,
      onPressed: onPressed,
    ),
  );
}
