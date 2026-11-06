import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../controllers/editor_notifier.dart';
import '../controllers/vim_controller.dart';
import '../../domain/markdown_document.dart';
import '../widgets/editor_pane.dart';
import '../widgets/editor_motion.dart';
import '../widgets/markdown_preview.dart';
import '../widgets/markdown_help.dart';
import '../widgets/notes_sidebar.dart';
import '../widgets/quick_search_dialog.dart';
import '../../../settings/presentation/views/settings_screen.dart';
import '../../../../core/first_run_config.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});
  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final EditorNotifier _editor;
  final _text = TextEditingController();
  final _editFocus = FocusNode(debugLabel: 'Editor');
  final _notesFocus = FocusNode(debugLabel: 'Notas');
  final _previewFocus = FocusNode(debugLabel: 'Vista previa');
  final _previewScroll = ScrollController();
  final _notesScroll = ScrollController();
  final _editableKey = GlobalKey<EditableTextState>();
  late final VimController _vim;
  late final AppLifecycleListener _lifecycle;
  String? _currentId;
  bool _sidebar = true;
  bool _previewVisible = true;
  final Set<String> _collapsedFolders = <String>{};
  double _soundVolume = 0.68;
  double? _previewTarget;
  int _scrollRevision = 0;
  Uint8List? _typingSound;
  String? _dropFolder;
  Timer? _dropFolderTimer;

  List<_SidebarEntry> get _sidebarEntries {
    final entries = <_SidebarEntry>[];
    final folders = <String>{};
    for (final note in _editor.notes) {
      final path = note.folder;
      if (path == null) continue;
      final segments = path.split('/');
      for (var i = 0; i < segments.length; i++) {
        folders.add(segments.take(i + 1).join('/'));
      }
    }
    void appendChildren(String? parent, int depth) {
      final children = folders.where((path) => _parentFolder(path) == parent);
      for (final folder in children) {
        entries.add(_SidebarEntry.folder(folder, depth));
        if (_collapsedFolders.contains(folder)) continue;
        appendChildren(folder, depth + 1);
        entries.addAll(
          _editor.notes
              .where((note) => note.folder == folder)
              .map((note) => _SidebarEntry.note(note, depth + 1)),
        );
      }
    }

    appendChildren(null, 0);
    entries.addAll(
      _editor.notes
          .where((note) => note.folder == null)
          .map((note) => _SidebarEntry.note(note, 0)),
    );
    return entries;
  }

  String? _parentFolder(String path) {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? null : path.substring(0, separator);
  }

  String _folderTitle(String path) => path.split('/').last;

  @override
  void initState() {
    super.initState();
    rootBundle
        .load('assets/sounds/creamy_sound_keyboard.wav')
        .then((data) async {
          _typingSound = data.buffer.asUint8List();
          const channel = MethodChannel('apuntes/keyboard');
          await channel.invokeMethod<void>('configure', _typingSound);
          _soundVolume =
              (await channel.invokeMethod<double>('getVolume')) ?? 0.68;
        })
        .catchError((_) {});
    _editor = ref.read(editorProvider);
    _vim = VimController(
      _text,
      onEdit: (value) => _editor.update(content: value),
      onSave: _editor.save,
      onCommand: _command,
      onSearch: _search,
      onLeftPane: _focusNotes,
      onRightPane: _focusPreview,
    );
    _editFocus.onKeyEvent = (node, event) {
      final shortcut = _handleGlobalShortcut(event);
      if (shortcut != KeyEventResult.ignored) return shortcut;
      if (event is KeyDownEvent &&
          event.character == '?' &&
          _vim.enabled &&
          !_vim.insert) {
        _help();
        return KeyEventResult.handled;
      }
      final result = _vim.handle(node, event);
      if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
          _soundVolume > 0 &&
          _vim.insert &&
          event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        unawaited(
          const MethodChannel(
            'apuntes/keyboard',
          ).invokeMethod<void>('click').catchError((_) {}),
        );
      }
      if (result == KeyEventResult.handled) _revealCursor();
      return result;
    };
    _editor.addListener(_sync);
    _sync();
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_editor.save()),
      onExitRequested: () async {
        await _editor.save();
        return _editor.saveStatus == 'Error al guardar'
            ? AppExitResponse.cancel
            : AppExitResponse.exit;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _sync() {
    if (!_editor.loading &&
        !_editor.loadFailed &&
        _currentId != _editor.selectedId) {
      _currentId = _editor.selectedId;
      _vim.load(_editor.note.content);
    }
  }

  void _revealCursor() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      _editableKey.currentState?.bringIntoView(
        TextPosition(offset: _vim.cursor),
      );
    }
  });
  void _focusNotes() {
    if (!_sidebar) setState(() => _sidebar = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notesFocus.requestFocus();
    });
  }

  void _newNote() {
    _editor.create();
    _vim.beginInsert();
    _editFocus.requestFocus();
  }

  Future<void> _newFolder({String? parentFolder}) async {
    final title = parentFolder == null
        ? 'Nueva carpeta'
        : 'Nueva subcarpeta en ${_folderTitle(parentFolder)}';
    final name = await _prompt(title, hint: 'Nombre de la carpeta');
    if (!mounted || name == null || name.trim().isEmpty) return;
    final segment = name.trim().replaceAll('/', '-');
    final folder = parentFolder == null ? segment : '$parentFolder/$segment';
    _editor.create(folder: folder);
    setState(() {
      _collapsedFolders.removeWhere(
        (path) => folder == path || folder.startsWith('$path/'),
      );
    });
    _vim.beginInsert();
    _editFocus.requestFocus();
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteNote(MarkdownDocument note) async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Eliminar nota',
      message:
          '¿Quieres eliminar «${note.title}»? Esta acción no se puede deshacer.',
      action: 'Eliminar',
    );
    if (!mounted || !confirmed) return;
    _editor.deleteNote(note.id);
    _editFocus.requestFocus();
  }

  Future<void> _deleteFolder(String folder) async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Eliminar carpeta',
      message:
          'Se eliminará «${_folderTitle(folder)}». Sus notas y subcarpetas se conservarán en la carpeta superior.',
      action: 'Eliminar carpeta',
    );
    if (!mounted || !confirmed) return;
    _editor.deleteFolder(folder);
    setState(() {
      _collapsedFolders.removeWhere(
        (path) => path == folder || path.startsWith('$folder/'),
      );
    });
  }

  bool _canDropIntoFolder(SidebarDragData data, String destination) {
    if (data.isFolder) {
      return data.value != destination &&
          !destination.startsWith('${data.value}/') &&
          _parentFolder(data.value) != destination;
    }
    final note = _editor.notes.where((item) => item.id == data.value);
    return note.isNotEmpty && note.first.folder != destination;
  }

  void _moveIntoFolder(SidebarDragData data, String destination) {
    if (data.isFolder) {
      _editor.moveFolderTo(data.value, destination);
    } else {
      _editor.moveToFolder(data.value, destination);
    }
    _dropFolderTimer?.cancel();
    setState(() {
      _collapsedFolders.removeWhere(
        (path) => destination == path || destination.startsWith('$path/'),
      );
      _dropFolder = destination;
    });
    _dropFolderTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _dropFolder = null);
    });
  }

  Future<void> _showSettings() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => SettingsScreen(
          initialVolume: _soundVolume,
          onVolumeChanged: (value) => setState(() => _soundVolume = value),
          initialNotesDirectory: NotesStorage.directory!,
          onNotesDirectoryChanged: _changeNotesDirectory,
        ),
      ),
    );
  }

  Future<void> _changeNotesDirectory(Directory directory) async {
    await _editor.changeStorageDirectory(
      directory,
      beforeSwitch: () => FirstRunConfig.persistNotesDirectory(directory.path),
    );
  }

  Future<String?> _prompt(
    String title, {
    String initial = '',
    String? hint,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            autofocus: true,
            placeholder: hint,
            controller: controller,
            onSubmitted: (text) => Navigator.pop(context, text),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _rename() async {
    final id = _editor.selectedId;
    final title = await _prompt(
      'Nombre de la nota',
      initial: _editor.note.title,
    );
    if (!mounted) return;
    if (title != null && title.trim().isNotEmpty && _editor.selectedId == id) {
      _editor.update(title: title.trim());
    }
    _editFocus.requestFocus();
  }

  Future<void> _help() async {
    await showMacosSheet<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MarkdownHelp(),
    );
    if (mounted) _editFocus.requestFocus();
  }

  Future<void> _search() async {
    final query = await _prompt('Buscar en esta nota', hint: 'Texto a buscar');
    if (!mounted) return;
    if (query != null) _vim.search(query);
    _editFocus.requestFocus();
    _revealCursor();
  }

  Future<void> _quickSearch() async {
    final hit = await showMacosSheet<QuickSearchHit>(
      context: context,
      barrierDismissible: true,
      builder: (_) => QuickSearchDialog(notes: _editor.notes),
    );
    if (!mounted || hit == null) return;
    if (hit.document case final note?) {
      _editor.select(note.id);
      _editFocus.requestFocus();
      return;
    }
    final folder = hit.folderPath;
    if (folder == null) return;
    setState(() {
      _sidebar = true;
      _collapsedFolders.removeWhere(
        (path) => folder == path || folder.startsWith('$path/'),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notesFocus.requestFocus();
    });
  }

  Future<void> _command() async {
    final command = await _prompt('Comando Vim', hint: 'w · new · help');
    if (!mounted) return;
    switch (command?.trim().replaceFirst(RegExp(r'^:'), '')) {
      case 'w':
        await _editor.save();
      case 'new':
        _newNote();
      case 'help':
        await _help();
      case null:
      case '':
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comandos disponibles: :w, :new, :help'),
          ),
        );
    }
    if (mounted) _editFocus.requestFocus();
  }

  KeyEventResult _notesKey(FocusNode node, KeyEvent event) {
    final shortcut = _handleGlobalShortcut(event);
    if (shortcut != KeyEventResult.ignored) return shortcut;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.character == 'l') {
      _editFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final direction =
        event.character == 'j' ||
            event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : event.character == 'k' ||
              event.logicalKey == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (direction == 0) return KeyEventResult.ignored;
    final visibleNotes = _sidebarEntries
        .map((entry) => entry.note)
        .whereType<MarkdownDocument>()
        .toList();
    if (visibleNotes.isEmpty) return KeyEventResult.ignored;
    final index =
        (visibleNotes.indexWhere((note) => note.id == _editor.selectedId) +
                direction)
            .clamp(0, visibleNotes.length - 1);
    _editor.select(visibleNotes[index].id);
    if (_notesScroll.hasClients) {
      final position = _notesScroll.position;
      final rowIndex = _sidebarEntries.indexWhere(
        (entry) => entry.note?.id == visibleNotes[index].id,
      );
      final top = rowIndex * 48.0;
      final bottom = top + 48;
      final target = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
          ? bottom - position.viewportDimension
          : position.pixels;
      _scrollTo(_notesScroll, target);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _previewKey(FocusNode node, KeyEvent event) {
    final shortcut = _handleGlobalShortcut(event);
    if (shortcut != KeyEventResult.ignored) return shortcut;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.character == 'h' ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _editFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.character == 'j'
        ? 60.0
        : event.character == 'k'
        ? -60.0
        : 0.0;
    if (delta == 0 || !_previewScroll.hasClients) return KeyEventResult.ignored;
    final target = ((_previewTarget ?? _previewScroll.offset) + delta).clamp(
      0.0,
      _previewScroll.position.maxScrollExtent,
    );
    _previewTarget = target;
    final revision = ++_scrollRevision;
    unawaited(
      _scrollTo(_previewScroll, target).whenComplete(() {
        if (revision == _scrollRevision) _previewTarget = null;
      }),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _handleGlobalShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _help();
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyN &&
        HardwareKeyboard.instance.isShiftPressed) {
      _newFolder();
    } else if (key == LogicalKeyboardKey.keyN) {
      _newNote();
    } else if (key == LogicalKeyboardKey.keyS) {
      unawaited(_editor.save());
    } else if (key == LogicalKeyboardKey.keyK) {
      _quickSearch();
    } else if (key == LogicalKeyboardKey.keyF) {
      _search();
    } else if (key == LogicalKeyboardKey.digit1) {
      _focusNotes();
    } else if (key == LogicalKeyboardKey.digit2) {
      _editFocus.requestFocus();
    } else if (key == LogicalKeyboardKey.digit3) {
      _focusPreview();
    } else if (key == LogicalKeyboardKey.comma) {
      _showSettings();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _scrollTo(ScrollController controller, double target) async {
    final offset = target.clamp(0.0, controller.position.maxScrollExtent);
    final duration = EditorMotion.duration(context, 110);
    if (duration == Duration.zero) {
      controller.jumpTo(offset);
    } else {
      await controller.animateTo(
        offset,
        duration: duration,
        curve: EditorMotion.curve,
      );
    }
  }

  void _toggleSidebar() {
    if (_sidebar && _notesFocus.hasFocus) _editFocus.requestFocus();
    setState(() => _sidebar = !_sidebar);
  }

  void _togglePreview() {
    setState(() => _previewVisible = !_previewVisible);
    if (!_previewVisible) _editFocus.requestFocus();
  }

  void _focusPreview() {
    if (!_previewVisible) setState(() => _previewVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _previewFocus.requestFocus();
    });
  }

  Widget _topBar(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_vim, _editor.saveStatusListenable]),
      builder: (context, _) => _buildTopBar(context),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: _sidebar ? 'Ocultar notas' : 'Mostrar notas',
            child: CupertinoButton(
              padding: const EdgeInsets.all(8),
              minimumSize: Size.zero,
              onPressed: _toggleSidebar,
              child: Icon(
                _sidebar
                    ? CupertinoIcons.sidebar_left
                    : CupertinoIcons.sidebar_right,
                size: 19,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 92,
            child: FadingLabel(
              _editor.saveStatus,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(10),
            color: _vim.enabled ? colors.secondaryContainer : null,
            onPressed: () {
              _vim.toggle();
              _editFocus.requestFocus();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_vim.enabled) ...[
                  Icon(
                    CupertinoIcons.check_mark,
                    size: 13,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  'Vim',
                  style: TextStyle(
                    fontSize: 12,
                    color: _vim.enabled ? colors.primary : colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _TopBarButton(
            icon: CupertinoIcons.search,
            tooltip: 'Búsqueda rápida (⌘K)',
            onPressed: _quickSearch,
          ),
          _TopBarButton(
            icon: CupertinoIcons.gear_alt,
            tooltip: 'Ajustes',
            onPressed: _showSettings,
          ),
          _TopBarButton(
            icon: CupertinoIcons.question_circle,
            tooltip: 'Ayuda de Markdown y teclado (F1)',
            onPressed: _help,
          ),
          _TopBarButton(
            icon: CupertinoIcons.ellipsis,
            tooltip: 'Archivo',
            onPressed: _showFileActions,
          ),
        ],
      ),
    );
  }

  Future<void> _showFileActions() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Archivo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'import'),
            child: const Text('Importar .md / .txt'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'export'),
            child: const Text('Exportar nota como .md'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'import') await _editor.importMarkdown();
    if (action == 'export') {
      final saved = await _editor.exportMarkdown();
      if (saved && mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            content: const Text('Nota exportada como Markdown.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _errorBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: colors.errorContainer,
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle, color: colors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(_editor.error!)),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            onPressed: _editor.save,
            child: const Text('Reintentar'),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            onPressed: _editor.clearError,
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dropFolderTimer?.cancel();
    _lifecycle.dispose();
    _editor.removeListener(_sync);
    _vim.dispose();
    _text.dispose();
    _editFocus.dispose();
    _notesFocus.dispose();
    _previewFocus.dispose();
    _previewScroll.dispose();
    _notesScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _editor,
    builder: (context, _) {
      if (_editor.loading) {
        return const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()),
        );
      }
      if (_editor.loadFailed) {
        return CupertinoPageScaffold(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_editor.error!),
                  const SizedBox(height: 16),
                  CupertinoButton.filled(
                    onPressed: _editor.load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: Column(
                children: [
                  if (_editor.error != null) _errorBanner(context),
                  Expanded(
                    child: Row(
                      children: [
                        AnimatedNotesPanel(
                          visible: _sidebar,
                          child: SizedBox(
                            width: 250,
                            child: NotesSidebar(
                              notes: _editor.notes,
                              selectedId: _editor.selectedId,
                              collapsedFolders: _collapsedFolders,
                              dropFolder: _dropFolder,
                              focusNode: _notesFocus,
                              scrollController: _notesScroll,
                              onKeyEvent: _notesKey,
                              onNewFolder: _newFolder,
                              onNewNote: _newNote,
                              onNewSubfolder: (folder) {
                                unawaited(_newFolder(parentFolder: folder));
                              },
                              onDeleteFolder: (folder) {
                                unawaited(_deleteFolder(folder));
                              },
                              onDeleteNote: (note) {
                                unawaited(_deleteNote(note));
                              },
                              onSelectNote: (note) {
                                _editor.select(note.id);
                                _editFocus.requestFocus();
                              },
                              onToggleFolder: (folder) => setState(() {
                                if (!_collapsedFolders.add(folder)) {
                                  _collapsedFolders.remove(folder);
                                }
                              }),
                              canDropIntoFolder: _canDropIntoFolder,
                              onDropIntoFolder: _moveIntoFolder,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                height: 42,
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 8,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Color(0xffe2e3e6),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _editor.note.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Renombrar nota',
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.all(7),
                                        minimumSize: Size.zero,
                                        onPressed: _rename,
                                        child: Icon(
                                          CupertinoIcons.pencil,
                                          size: 15,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) => Row(
                                    children: [
                                      Expanded(
                                        child: ListenableBuilder(
                                          listenable: _vim,
                                          builder: (context, _) => EditorPane(
                                            vim: _vim,
                                            focusNode: _editFocus,
                                            editableKey: _editableKey,
                                            previewVisible: _previewVisible,
                                            onTogglePreview: _togglePreview,
                                          ),
                                        ),
                                      ),
                                      AnimatedContainer(
                                        duration: EditorMotion.duration(
                                          context,
                                          220,
                                        ),
                                        curve: EditorMotion.curve,
                                        width: _previewVisible
                                            ? constraints.maxWidth / 2
                                            : 0,
                                        child: _previewVisible
                                            ? Row(
                                                children: [
                                                  const VerticalDivider(
                                                    width: 1,
                                                    thickness: 1,
                                                  ),
                                                  Expanded(
                                                    child: Focus(
                                                      focusNode: _previewFocus,
                                                      onKeyEvent: _previewKey,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          SizedBox(
                                                            height: 42,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        20,
                                                                  ),
                                                              child: Align(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: Text(
                                                                  'VISTA PREVIA',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Theme.of(
                                                                      context,
                                                                    ).colorScheme.onSurfaceVariant,
                                                                    letterSpacing:
                                                                        1,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: ValueListenableBuilder<String>(
                                                              valueListenable:
                                                                  _editor
                                                                      .contentListenable,
                                                              builder:
                                                                  (
                                                                    context,
                                                                    content,
                                                                    _,
                                                                  ) => MarkdownPreview(
                                                                    controller:
                                                                        _previewScroll,
                                                                    content:
                                                                        content,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SidebarEntry {
  const _SidebarEntry.folder(String value, this.depth)
    : folder = value,
      note = null;
  const _SidebarEntry.note(MarkdownDocument value, this.depth)
    : folder = null,
      note = value;

  final String? folder;
  final MarkdownDocument? note;
  final int depth;
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
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
      onPressed: onPressed,
      icon: icon,
      size: 19,
    ),
  );
}
