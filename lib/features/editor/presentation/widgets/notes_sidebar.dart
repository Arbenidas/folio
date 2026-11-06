import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material, Theme;
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../../domain/markdown_document.dart';
import 'editor_motion.dart';

class SidebarDragData {
  const SidebarDragData.note(this.value) : isFolder = false;
  const SidebarDragData.folder(this.value) : isFolder = true;

  final String value;
  final bool isFolder;
}

class NotesSidebar extends StatelessWidget {
  const NotesSidebar({
    super.key,
    required this.notes,
    required this.selectedId,
    required this.collapsedFolders,
    required this.dropFolder,
    required this.focusNode,
    required this.scrollController,
    required this.onKeyEvent,
    required this.onNewFolder,
    required this.onNewNote,
    required this.onNewSubfolder,
    required this.onDeleteFolder,
    required this.onDeleteNote,
    required this.onSelectNote,
    required this.onToggleFolder,
    required this.canDropIntoFolder,
    required this.onDropIntoFolder,
  });

  final List<MarkdownDocument> notes;
  final String? selectedId;
  final Set<String> collapsedFolders;
  final String? dropFolder;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final FocusOnKeyEventCallback onKeyEvent;
  final VoidCallback onNewFolder;
  final VoidCallback onNewNote;
  final ValueChanged<String> onNewSubfolder;
  final ValueChanged<String> onDeleteFolder;
  final ValueChanged<MarkdownDocument> onDeleteNote;
  final ValueChanged<MarkdownDocument> onSelectNote;
  final ValueChanged<String> onToggleFolder;
  final bool Function(SidebarDragData, String) canDropIntoFolder;
  final void Function(SidebarDragData, String) onDropIntoFolder;

  List<String> get _folderPaths {
    final paths = <String>{};
    for (final note in notes) {
      final path = note.folder;
      if (path == null) continue;
      final segments = path.split('/');
      for (var i = 0; i < segments.length; i++) {
        paths.add(segments.take(i + 1).join('/'));
      }
    }
    return paths.toList();
  }

  String? _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? null : path.substring(0, slash);
  }

  String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 5, 10, 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'NOTAS',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
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
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
                children: [
                  ..._childrenOf(context, null, 0),
                  for (final note in notes.where((note) => note.folder == null))
                    _noteRow(context, note, 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _childrenOf(BuildContext context, String? parent, int depth) => [
    for (final folder in _folderPaths.where(
      (path) => _parentOf(path) == parent,
    ))
      _folderRow(context, folder, depth),
    for (final note in notes.where((note) => note.folder == parent))
      if (parent != null) _noteRow(context, note, depth - 1),
  ];

  Widget _folderRow(BuildContext context, String path, int depth) {
    final colors = Theme.of(context).colorScheme;
    final expanded = !collapsedFolders.contains(path);
    return Draggable<SidebarDragData>(
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
          return Padding(
            padding: EdgeInsets.only(left: depth * 14),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: EditorMotion.duration(context, 170),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
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
                        AnimatedRotation(
                          turns: expanded ? 0 : -0.25,
                          duration: EditorMotion.duration(context, 190),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 7),
                        AnimatedSwitcher(
                          duration: EditorMotion.duration(context, 150),
                          child: Icon(
                            hovering || justDropped
                                ? CupertinoIcons.folder_badge_plus
                                : expanded
                                ? CupertinoIcons.folder_open
                                : CupertinoIcons.folder,
                            key: ValueKey((hovering, expanded)),
                            size: 17,
                            color: hovering || justDropped
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _nameOf(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AppIconButton(
                          padding: const EdgeInsets.all(4),
                          semanticLabel: 'Acciones de ${_nameOf(path)}',
                          icon: CupertinoIcons.ellipsis,
                          size: 16,
                          onPressed: () => _showFolderActions(context, path),
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

  Future<void> _showFolderActions(BuildContext context, String path) =>
      showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(_nameOf(path)),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onNewSubfolder(path);
              },
              child: const Text('Nueva subcarpeta'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                onDeleteFolder(path);
              },
              child: const Text('Eliminar carpeta'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ),
      );

  Widget _noteRow(BuildContext context, MarkdownDocument note, int depth) {
    final colors = Theme.of(context).colorScheme;
    final selected = note.id == selectedId;
    return Padding(
      padding: EdgeInsets.only(left: note.folder == null ? 0 : 20 + depth * 14),
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
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          borderRadius: BorderRadius.circular(10),
          pressedOpacity: 0.72,
          onPressed: () => onSelectNote(note),
          child: AnimatedContainer(
            duration: EditorMotion.duration(context, 190),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? colors.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? CupertinoIcons.doc_text_fill
                            : CupertinoIcons.doc_text,
                        size: 16,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: EditorMotion.duration(context, 170),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected ? colors.primary : colors.onSurface,
                          ),
                          child: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  padding: const EdgeInsets.all(4),
                  semanticLabel: 'Acciones de ${note.title}',
                  icon: CupertinoIcons.ellipsis,
                  size: 15,
                  onPressed: () => _showNoteActions(context, note),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNoteActions(BuildContext context, MarkdownDocument note) =>
      showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(note.title),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                onDeleteNote(note);
              },
              child: const Text('Eliminar nota'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ),
      );
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
