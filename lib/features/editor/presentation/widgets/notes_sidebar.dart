import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        Material,
        Scrollbar,
        ScrollbarTheme,
        ScrollbarThemeData,
        Theme;
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../tasks/domain/managed_task.dart';
import '../../domain/markdown_document.dart';
import 'editor_action_menu.dart';
import 'editor_motion.dart';

class SidebarDragData {
  const SidebarDragData.note(this.value) : isFolder = false;
  const SidebarDragData.folder(this.value) : isFolder = true;

  final String value;
  final bool isFolder;
}

enum _NoteAction { rename, publish, delete }

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
    required this.onPublishNote,
    required this.onDeleteFolder,
    required this.onDeleteNote,
    required this.onSelectNote,
    required this.onToggleFolder,
    required this.canDropIntoFolder,
    required this.onDropIntoFolder,
    this.inProgressTasks = const [],
    this.taskCount = 0,
    this.onOpenTasks,
    this.onOpenTaskNote,
    this.onOpenDailyNote,
    this.onQuickSearch,
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
  final ValueChanged<MarkdownDocument> onPublishNote;
  final ValueChanged<String> onDeleteFolder;
  final ValueChanged<MarkdownDocument> onDeleteNote;
  final ValueChanged<MarkdownDocument> onSelectNote;
  final ValueChanged<String> onToggleFolder;
  final bool Function(SidebarDragData, String) canDropIntoFolder;
  final void Function(SidebarDragData, String) onDropIntoFolder;
  final List<ManagedTask> inProgressTasks;
  final int taskCount;
  final VoidCallback? onOpenTasks;
  final ValueChanged<ManagedTask>? onOpenTaskNote;
  final VoidCallback? onOpenDailyNote;
  final VoidCallback? onQuickSearch;

  String? _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? null : path.substring(0, slash);
  }

  String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  int _noteCountInFolder(String path) {
    final prefix = '$path/';
    return notes
        .where(
          (note) =>
              note.folder == path || (note.folder?.startsWith(prefix) ?? false),
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final tree = ListView(
      controller: scrollController,
      padding: switch (style.kind) {
        AppStyle.retro => const EdgeInsets.fromLTRB(10, 8, 12, 14),
        AppStyle.pop => const EdgeInsets.fromLTRB(10, 10, 12, 14),
        AppStyle.clasico => const EdgeInsets.fromLTRB(10, 6, 10, 14),
      },
      children: _childrenOf(context, null, 0),
    );
    return Container(
      color: colors.surfaceContainerLow,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
            decoration: style.isGraphic
                ? BoxDecoration(
                    color: style.isPop
                        ? style.folderAccent(3)
                        : colors.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: style.ink,
                        width: style.lineWidth,
                      ),
                    ),
                  )
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: EditorMotion.duration(context, 140),
                  width: focusNode.hasFocus ? 6 : 0,
                  height: 6,
                  margin: EdgeInsets.only(right: focusNode.hasFocus ? 6 : 0),
                  decoration: BoxDecoration(
                    color: focusNode.hasFocus
                        ? colors.primary
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  'NOTAS',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: style.isRetro ? 'Menlo' : null,
                    color: style.isPop
                        ? style.folderForeground(3)
                        : focusNode.hasFocus
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    letterSpacing: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: style.isPop
                        ? colors.surface.withValues(alpha: 0.72)
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${notes.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: style.isPop
                          ? style.folderForeground(3)
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                if (onOpenDailyNote != null) ...[
                  _SidebarAction(
                    icon: CupertinoIcons.calendar_today,
                    tooltip: 'Nota de hoy (⌘D)',
                    onPressed: onOpenDailyNote!,
                  ),
                  const SizedBox(width: 2),
                ],
                _SidebarAction(
                  icon: CupertinoIcons.folder_badge_plus,
                  tooltip: 'Nueva carpeta',
                  onPressed: onNewFolder,
                ),
                const SizedBox(width: 2),
                _SidebarAction(
                  icon: CupertinoIcons.add,
                  tooltip: 'Nueva nota (⌘N)',
                  onPressed: onNewNote,
                ),
              ],
            ),
          ),
          if (onQuickSearch != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: _SidebarSearchTrigger(onPressed: onQuickSearch!),
            ),
          Expanded(
            child: Focus(
              focusNode: focusNode,
              onKeyEvent: onKeyEvent,
              child: style.isRetro
                  ? ScrollbarTheme(
                      data: ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll(
                          style.ink.withValues(alpha: 0.55),
                        ),
                        trackColor: WidgetStatePropertyAll(
                          colors.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Scrollbar(
                        controller: scrollController,
                        thickness: 6,
                        radius: const Radius.circular(3),
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
          _InProgressTasks(
            tasks: inProgressTasks,
            taskCount: taskCount,
            onOpenTasks: onOpenTasks,
            onOpenTaskNote: onOpenTaskNote,
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
            ink: style.ink.withValues(alpha: 0.42),
            isLast: index == rows.length - 1,
            isFolder: index < folders.length,
          ),
          child: Padding(padding: const EdgeInsets.only(left: 16), child: row),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.folder, size: 16),
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
                _HoverableRow(
                  builder: (context, rowHovered) {
                    final count = _noteCountInFolder(path);
                    return AnimatedContainer(
                      duration: EditorMotion.duration(context, 150),
                      curve: Curves.easeOutCubic,
                      margin: EdgeInsets.symmetric(
                        vertical: style.isPop ? 4 : 2,
                      ),
                      decoration: style.isPop
                          ? style.panel(
                              hovering
                                  ? colors.tertiaryContainer
                                  : colors.surface,
                              lift: 2.5,
                            )
                          : BoxDecoration(
                              color: hovering
                                  ? colors.tertiaryContainer
                                  : justDropped
                                  ? colors.secondaryContainer
                                  : rowHovered
                                  ? colors.surfaceContainerHigh.withValues(
                                      alpha: 0.72,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                      child: GestureDetector(
                        onSecondaryTapUp: (details) => _showFolderActions(
                          context,
                          path,
                          details.globalPosition,
                        ),
                        child: CupertinoButton(
                          padding: const EdgeInsets.fromLTRB(9, 8.5, 5, 8.5),
                          minimumSize: Size.zero,
                          alignment: Alignment.centerLeft,
                          borderRadius: BorderRadius.circular(9),
                          pressedOpacity: 0.72,
                          onPressed: () => onToggleFolder(path),
                          child: Row(
                            children: [
                              if (style.isRetro)
                                Icon(
                                  expanded
                                      ? CupertinoIcons.minus_square
                                      : CupertinoIcons.plus_square,
                                  size: 14,
                                  color: foreground.withValues(alpha: 0.78),
                                )
                              else
                                AnimatedRotation(
                                  turns: expanded ? 0 : -0.25,
                                  duration: EditorMotion.duration(context, 180),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(width: 7),
                              Container(
                                padding: style.isPop
                                    ? const EdgeInsets.all(4)
                                    : null,
                                decoration: style.isPop
                                    ? style.panel(tab)
                                    : null,
                                child: Icon(
                                  hovering || justDropped
                                      ? CupertinoIcons.folder_badge_plus
                                      : expanded
                                      ? CupertinoIcons.folder_open
                                      : CupertinoIcons.folder,
                                  size: 19,
                                  color: style.isPop
                                      ? style.folderForeground(tabIndex)
                                      : hovering || justDropped
                                      ? foreground
                                      : colors.primary.withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _nameOf(path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: foreground,
                                  ),
                                ),
                              ),
                              if (!rowHovered && !hovering && count > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurfaceVariant.withValues(
                                        alpha: 0.65,
                                      ),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              AnimatedOpacity(
                                opacity: rowHovered || hovering ? 1 : 0,
                                alwaysIncludeSemantics: true,
                                duration: EditorMotion.duration(context, 120),
                                child: Builder(
                                  builder: (buttonContext) => AppIconButton(
                                    padding: const EdgeInsets.all(4),
                                    semanticLabel:
                                        'Acciones de ${_nameOf(path)}',
                                    icon: CupertinoIcons.ellipsis,
                                    size: 16,
                                    onPressed: () => _showFolderActions(
                                      context,
                                      path,
                                      editorMenuAnchor(buttonContext),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: EditorMotion.duration(context, 210),
                    curve: EditorMotion.emphasizedCurve,
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
        left: style.isRetro || note.folder == null ? 0 : 18 + depth * 14,
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
              width: 240,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.doc_text, size: 17),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: const SizedBox(height: 40),
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showNoteActions(context, note, details.globalPosition),
          child: _HoverableRow(
            builder: (context, hovered) => AnimatedContainer(
              duration: EditorMotion.duration(context, 140),
              curve: EditorMotion.curve,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: style.isGraphic && selected
                  ? BoxDecoration(
                      color: style.isRetro
                          ? colors.surfaceContainerHighest.withValues(
                              alpha: 0.72,
                            )
                          : colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(
                        style.isRetro ? 8 : 10,
                      ),
                      border: Border.all(
                        color: style.ink.withValues(
                          alpha: style.isRetro ? 0.75 : 1,
                        ),
                        width: style.isRetro ? 1.4 : style.lineWidth,
                      ),
                      boxShadow: style.isPop
                          ? [
                              BoxShadow(
                                color: style.shadow,
                                offset: const Offset(2, 2),
                              ),
                            ]
                          : null,
                    )
                  : BoxDecoration(
                      color: selected
                          ? colors.secondaryContainer
                          : hovered
                          ? colors.surfaceContainerHigh.withValues(alpha: 0.7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
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
                        padding: const EdgeInsets.fromLTRB(10, 8.5, 4, 8.5),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: () => onSelectNote(note),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? CupertinoIcons.doc_text_fill
                                  : CupertinoIcons.doc_text,
                              size: 17.5,
                              color: selected
                                  ? (style.isRetro
                                        ? colors.primary
                                        : foreground)
                                  : colors.onSurfaceVariant.withValues(
                                      alpha: 0.82,
                                    ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                note.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.34,
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
                  AnimatedOpacity(
                    opacity: hovered || selected ? 1 : 0,
                    alwaysIncludeSemantics: true,
                    duration: EditorMotion.duration(context, 120),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Builder(
                        builder: (buttonContext) => AppIconButton(
                          padding: const EdgeInsets.all(4),
                          semanticLabel: 'Acciones de ${note.title}',
                          icon: CupertinoIcons.ellipsis,
                          size: 16,
                          onPressed: () => _showNoteActions(
                            context,
                            note,
                            editorMenuAnchor(buttonContext),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
          _NoteAction.publish,
          CupertinoIcons.globe,
          'Publicar en arbe.blog…',
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
      case _NoteAction.publish:
        onPublishNote(note);
      case _NoteAction.delete:
        onDeleteNote(note);
      case null:
        break;
    }
  }
}

class _InProgressTasks extends StatefulWidget {
  const _InProgressTasks({
    required this.tasks,
    required this.taskCount,
    required this.onOpenTasks,
    required this.onOpenTaskNote,
  });

  final List<ManagedTask> tasks;
  final int taskCount;
  final VoidCallback? onOpenTasks;
  final ValueChanged<ManagedTask>? onOpenTaskNote;

  @override
  State<_InProgressTasks> createState() => _InProgressTasksState();
}

class _InProgressTasksState extends State<_InProgressTasks> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: style.isGraphic
              ? style.ink.withValues(alpha: 0.35)
              : colors.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
            minimumSize: Size.zero,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: EditorMotion.duration(context, 160),
                  curve: EditorMotion.curve,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'EN CURSO',
                    style: TextStyle(
                      fontFamily: style.isRetro ? 'Menlo' : null,
                      fontSize: 11.5,
                      letterSpacing: 1.05,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.taskCount > 0
                        ? colors.primaryContainer.withValues(alpha: 0.85)
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.taskCount}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: widget.taskCount > 0
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: EditorMotion.duration(context, 180),
              curve: EditorMotion.emphasizedCurve,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.tasks.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Sin tareas en curso',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.78,
                                  ),
                                  fontSize: 12.5,
                                ),
                              ),
                            )
                          else ...[
                            for (final task in widget.tasks.take(3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3.5,
                                        ),
                                        minimumSize: Size.zero,
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        onPressed: widget.onOpenTasks,
                                        child: Text(
                                          task.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.onSurface,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (task.noteId != null)
                                      CupertinoButton(
                                        padding: const EdgeInsets.all(4),
                                        minimumSize: Size.zero,
                                        onPressed: () =>
                                            widget.onOpenTaskNote?.call(task),
                                        child: Icon(
                                          CupertinoIcons.arrow_up_right_square,
                                          size: 15,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 5),
                          ],
                          _HoverableRow(
                            builder: (context, hovered) => CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: widget.onOpenTasks,
                              child: AnimatedContainer(
                                duration: EditorMotion.duration(context, 140),
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: hovered
                                      ? colors.primaryContainer
                                      : colors.primaryContainer.withValues(
                                          alpha: 0.6,
                                        ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Ver tareas',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colors.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      CupertinoIcons.arrow_right,
                                      size: 14,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
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
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    final join = isFolder && size.height > 36 ? 16.0 : size.height / 2;
    canvas.drawLine(
      const Offset(9, 0),
      Offset(9, isLast ? join : size.height),
      pen,
    );
    canvas.drawLine(Offset(9, join), Offset(16, join), pen);
  }

  @override
  bool shouldRepaint(_TreeBranch oldDelegate) =>
      ink != oldDelegate.ink ||
      isLast != oldDelegate.isLast ||
      isFolder != oldDelegate.isFolder;
}

class _HoverableRow extends StatefulWidget {
  const _HoverableRow({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverableRow> createState() => _HoverableRowState();
}

class _HoverableRowState extends State<_HoverableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

class _SidebarSearchTrigger extends StatelessWidget {
  const _SidebarSearchTrigger({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return _HoverableRow(
      builder: (context, hovered) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 140),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hovered
                ? colors.surfaceContainerHigh
                : colors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: style.isGraphic
                  ? style.ink.withValues(alpha: 0.4)
                  : colors.outlineVariant.withValues(alpha: 0.78),
            ),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.search,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Buscar notas…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.82),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '⌘K',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      size: 17.5,
      padding: const EdgeInsets.all(6),
      onPressed: onPressed,
    ),
  );
}
