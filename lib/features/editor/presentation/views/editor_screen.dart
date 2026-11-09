import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/folio_window_chrome.dart';
import '../../../../core/theme.dart';
import '../controllers/editor_notifier.dart';
import '../controllers/vim_controller.dart';
import '../../domain/markdown_document.dart';
import '../../domain/note_template.dart';
import '../../domain/trashed_note.dart';
import '../../data/recovered_drafts_repository.dart';
import '../widgets/editor_pane.dart';
import '../widgets/editor_action_menu.dart';
import '../widgets/editor_motion.dart';
import '../widgets/markdown_preview.dart';
import '../widgets/markdown_help.dart';
import '../widgets/notes_sidebar.dart';
import '../widgets/quick_search_dialog.dart';
import '../widgets/template_picker.dart';
import '../../../settings/presentation/views/settings_screen.dart';
import '../../../../core/first_run_config.dart';
import '../../../../core/onboarding_preferences.dart';
import '../../../../core/vim_preferences.dart';
import '../../../onboarding/presentation/widgets/first_run_tour.dart';

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
  int _vimPreferenceRevision = 0;
  String _focusedPane = 'editor';
  bool _editorInteractedBeforePreferencesLoad = false;
  Timer? _dropFolderTimer;

  List<_SidebarEntry> get _sidebarEntries {
    final entries = <_SidebarEntry>[];
    final folders = _editor.folderPaths;
    void appendChildren(String? parent, int depth) {
      final children =
          folders.where((path) => _parentFolder(path) == parent).toList()..sort(
            (a, b) =>
                _folderTitle(a)
                    .toLowerCase()
                    .compareTo(_folderTitle(b).toLowerCase()),
          );
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
      onEdit: (value) {
        _editorInteractedBeforePreferencesLoad = true;
        _editor.update(content: value);
      },
      onSave: _editor.save,
      onCommand: _command,
      onSearch: _search,
      onLeftPane: _focusNotes,
      onRightPane: _focusPreview,
      onPreferencesChanged: (enabled, lastSearch) {
        _vimPreferenceRevision++;
        unawaited(
          VimPreferences.save(enabled: enabled, lastSearch: lastSearch),
        );
      },
    );
    _editFocus.onKeyEvent = (node, event) {
      _vim.recordKeyEvent(event);
      final shortcut = _handleGlobalShortcut(event);
      if (shortcut != KeyEventResult.ignored) return shortcut;
      final keyboard = HardwareKeyboard.instance;
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyV &&
          keyboard.isMetaPressed &&
          !keyboard.isShiftPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isControlPressed) {
        unawaited(_paste());
        return KeyEventResult.handled;
      }
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
          const MethodChannel('apuntes/keyboard')
              .invokeMethod<void>('click')
              .catchError((_) {}),
        );
      }
      if (result == KeyEventResult.handled) _revealCursor();
      return result;
    };
    _editor.addListener(_sync);
    _editFocus.addListener(() {
      if (_editFocus.hasFocus) {
        _focusedPane = 'editor';
      } else {
        _vim.clearHeldModifiers();
      }
    });
    _notesFocus.addListener(() {
      if (_notesFocus.hasFocus) _focusedPane = 'notes';
    });
    _previewFocus.addListener(() {
      if (_previewFocus.hasFocus) _focusedPane = 'preview';
    });
    _sync();
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_editor.save()),
      onResume: () async {
        await _editor.refresh();
        if (mounted) _restoreEditorFocus();
      },
      onExitRequested: () async {
        await _editor.save();
        return _editor.saveStatus == 'Error al guardar'
            ? AppExitResponse.cancel
            : AppExitResponse.exit;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocus.requestFocus();
      unawaited(_restoreVimPreferences());
      unawaited(_showTourIfNeeded());
    });
  }

  Future<void> _restoreVimPreferences() async {
    final revision = _vimPreferenceRevision;
    final preferences = await VimPreferences.load();
    if (mounted &&
        revision == _vimPreferenceRevision &&
        !_editorInteractedBeforePreferencesLoad) {
      _vim.restorePreferences(
        enabled: preferences.enabled,
        lastSearch: preferences.lastSearch,
      );
    }
  }

  void _restoreEditorFocus() {
    switch (_focusedPane) {
      case 'notes':
        _notesFocus.requestFocus();
      case 'preview':
        _previewFocus.requestFocus();
      default:
        _editFocus.requestFocus();
    }
  }

  Future<void> _showTourIfNeeded() async {
    if (await OnboardingPreferences.tourCompleted() || !mounted) return;
    await showFirstRunTour(context);
    if (mounted) _editFocus.requestFocus();
  }

  void _sync() {
    final content = _editor.selectedNote?.content ?? '';
    if (!_editor.loading &&
        !_editor.loadFailed &&
        (_currentId != _editor.selectedId || _text.text != content)) {
      _currentId = _editor.selectedId;
      _vim.load(content);
    }
  }

  Future<void> _paste() async {
    final id = _editor.selectedId;
    if (id == null) return;
    final repository = _editor.repository;
    final original = _text.value;
    bool stillEditing() =>
        mounted &&
        _editFocus.hasFocus &&
        _editor.repository == repository &&
        _editor.selectedId == id &&
        _text.value == original;

    Uint8List? png;
    try {
      png = await const MethodChannel('folio/clipboard')
          .invokeMethod<Uint8List>('readPng');
    } on MissingPluginException {
      // Text paste remains available when the native image channel is absent.
    } on PlatformException catch (error) {
      if (mounted) {
        _editor.reportError(
          error.message ?? 'No se pudo leer el portapapeles.',
        );
      }
      return;
    }
    if (!stillEditing()) return;
    if (png == null) {
      if (!_vim.enabled || _vim.insert) {
        await _editableKey.currentState?.pasteText(
          SelectionChangedCause.keyboard,
        );
      }
      return;
    }
    final reference = await _editor.saveImage(id, png);
    if (!stillEditing() || reference == null) return;
    final selection = original.selection;
    final start = selection.isValid ? selection.start : original.text.length;
    final end = selection.isValid ? selection.end : start;
    final image = '![Captura]($reference)';
    _text.value = TextEditingValue(
      text: original.text.replaceRange(start, end, image),
      selection: TextSelection.collapsed(offset: start + image.length),
    );
    _revealCursor();
  }

  void _toggleTask(String id, String source, int offset) {
    if (_editor.selectedId != id ||
        _text.text != source ||
        offset < 0 ||
        offset >= source.length) {
      return;
    }
    final marker = source[offset];
    if (marker != ' ' && marker != 'x' && marker != 'X') return;
    _text.value = _text.value.copyWith(
      text: source.replaceRange(offset, offset + 1, marker == ' ' ? 'x' : ' '),
      composing: TextRange.empty,
    );
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

  Future<void> _newNote({String? folder, NoteTemplate? template}) async {
    await _editor.create(
      folder: folder,
      title: template?.title ?? 'Nueva nota',
      content: template?.content ?? '',
    );
    if (!mounted || _editor.selectedNote == null) return;
    _vim.beginInsert();
    _editFocus.requestFocus();
  }

  Future<void> _newFromTemplate() async {
    final template = await showDialog<NoteTemplate>(
      context: context,
      animationStyle: EditorMotion.dialog(context),
      builder: (context) => const TemplatePicker(),
    );
    if (mounted && template != null) {
      await _newNote(folder: _editor.selectedNote?.folder, template: template);
    }
  }

  Future<void> _renameFolder(String folder) async {
    final title = await _prompt(
      'Renombrar carpeta',
      initial: _folderTitle(folder),
      hint: 'Nombre de la carpeta',
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    await _editor.renameFolder(folder, title.trim());
    setState(
      () => _collapsedFolders.removeWhere(
        (path) => path == folder || path.startsWith('$folder/'),
      ),
    );
  }

  Future<void> _newFolder({String? parentFolder}) async {
    final title = parentFolder == null
        ? 'Nueva carpeta'
        : 'Nueva subcarpeta en ${_folderTitle(parentFolder)}';
    final name = await _prompt(title, hint: 'Nombre de la carpeta');
    if (!mounted || name == null || name.trim().isEmpty) return;
    final segment = name.trim().replaceAll('/', '-');
    final folder = parentFolder == null ? segment : '$parentFolder/$segment';
    final actualFolder = await _editor.createFolder(folder);
    if (actualFolder == null || !mounted) return;
    setState(() {
      _collapsedFolders.removeWhere(
        (path) => actualFolder == path || actualFolder.startsWith('$path/'),
      );
    });
    _notesFocus.requestFocus();
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
      title: 'Mover nota a la papelera',
      message: 'Puedes restaurar «${note.title}» desde Archivo → Papelera.',
      action: 'Mover a la papelera',
    );
    if (!mounted || !confirmed) return;
    await _editor.deleteNote(note.id);
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
    await _editor.deleteFolder(folder);
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
      unawaited(_editor.moveFolderTo(data.value, destination));
    } else {
      unawaited(_editor.moveToFolder(data.value, destination));
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

  Future<void> _recoverStorageLocation() async {
    try {
      final currentPath = NotesStorage.directory?.path ?? '';
      final path = await FirstRunConfig.chooseNotesDirectory(currentPath);
      if (!mounted || path == null) return;
      await _editor.reselectStorageDirectory(
        Directory(path),
        beforeSwitch: () => FirstRunConfig.persistNotesDirectory(path),
      );
    } catch (error) {
      if (!mounted) return;
      _editor.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir esa ubicación: $error')),
      );
    }
  }

  Future<String?> _prompt(
    String title, {
    String initial = '',
    String? hint,
  }) async {
    final controller = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    final route = CupertinoDialogRoute<String>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CupertinoTextField(
              autofocus: true,
              placeholder: hint,
              style: TextStyle(color: colors.onSurface),
              placeholderStyle: TextStyle(color: colors.onSurfaceVariant),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                border: Border.all(color: colors.outline),
                borderRadius: BorderRadius.circular(6),
              ),
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
        );
      },
    );
    final result = Navigator.of(context, rootNavigator: true).push(route);
    unawaited(route.completed.whenComplete(controller.dispose));
    return result;
  }

  Future<void> _renameNote(MarkdownDocument note) async {
    final title = await _prompt('Renombrar nota', initial: note.title);
    final name = title?.trim();
    if (!mounted || name == null || name.isEmpty || name == note.title) return;
    await _editor.renameNote(note.id, name);
  }

  Future<void> _help() async {
    await showMacosSheet<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MarkdownHelp(
        onReplayTour: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(showFirstRunTour(context));
          });
        },
      ),
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
    final hit = await showGeneralDialog<QuickSearchHit>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar búsqueda',
      barrierColor: Colors.black38,
      transitionDuration: EditorMotion.duration(context, 150),
      pageBuilder: (_, _, _) => QuickSearchDialog(notes: _editor.notes),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      ),
    );
    if (!mounted || hit == null) return;
    if (hit.document case final note?) {
      _editor.select(note.id);
      if (_editor.selectedId != note.id) return;
      _editFocus.requestFocus();
      final match = QuickSearchHit.findContent(_text.text, hit.contentQuery!);
      if (match != null) {
        _text.selection = TextSelection.collapsed(offset: match.start);
        _revealCursor();
      }
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
    if (_vim.enabled &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyH) {
        _focusNotes();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        _focusPreview();
        return KeyEventResult.handled;
      }
    }
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
    final style = FolioStyle.of(context);
    final toolbarForeground = style.isPop ? style.onAccent : colors.onSurface;
    return Container(
      height: FolioWindowChrome.isSupported
          ? FolioWindowChrome.toolbarHeight
          : style.isRetro
          ? 46
          : 58,
      padding: EdgeInsetsDirectional.only(
        start: FolioWindowChrome.isSupported
            ? FolioWindowChrome.trafficLightInset
            : 10,
        end: 10,
      ),
      decoration: BoxDecoration(
        color: style.isPop ? style.accent : colors.surface,
        border: Border(
          bottom: BorderSide(
            color: style.isGraphic ? style.ink : colors.outlineVariant,
            width: style.isGraphic ? style.lineWidth : 1,
          ),
        ),
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
                color: toolbarForeground,
              ),
            ),
          ),
          if (FolioWindowChrome.isSupported || style.isGraphic) ...[
            const SizedBox(width: 8),
            Text(
              style.isRetro ? 'FOLIO' : 'Folio',
              style: TextStyle(
                fontFamily: style.isRetro ? 'Menlo' : null,
                fontSize: FolioWindowChrome.isSupported
                    ? 13
                    : style.isRetro
                    ? 15
                    : 24,
                fontWeight: FontWeight.w800,
                color: toolbarForeground,
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: 92,
            child: FadingLabel(
              _editor.saveStatus,
              style: TextStyle(fontSize: 11, color: toolbarForeground),
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
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  'Vim',
                  style: TextStyle(
                    fontSize: 12,
                    color: _vim.enabled
                        ? colors.onSecondaryContainer
                        : toolbarForeground,
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
          Builder(
            builder: (buttonContext) => _TopBarButton(
              icon: CupertinoIcons.ellipsis,
              tooltip: 'Archivo',
              onPressed: () => _showFileActions(buttonContext),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileActions(BuildContext buttonContext) async {
    final action = await showEditorActionMenu<String>(
      buttonContext,
      editorMenuAnchor(buttonContext),
      [
        editorActionItem(
          'template',
          CupertinoIcons.doc_on_doc,
          'Nueva nota desde plantilla…',
        ),
        editorActionItem(
          'import',
          CupertinoIcons.arrow_down_to_line,
          'Importar .md / .txt',
        ),
        editorActionItem(
          'export',
          CupertinoIcons.arrow_up_to_line,
          'Exportar nota como .md',
        ),
        editorActionItem(
          'recovery',
          CupertinoIcons.clock,
          'Notas recuperadas (${_editor.recoveredDrafts.length})',
        ),
        editorActionItem('trash', CupertinoIcons.trash, 'Papelera'),
      ],
    );
    if (!mounted) return;
    if (action == 'template') await _newFromTemplate();
    if (action == 'trash') await _showTrash();
    if (action == 'recovery') await _showRecoveredDrafts();
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

  Future<void> _showTrash() async {
    final List<TrashedNote> notes;
    try {
      notes = await _editor.listTrash();
    } catch (error) {
      if (mounted) _editor.reportError('No se pudo abrir la papelera: $error');
      return;
    }
    if (!mounted) return;
    final note = await showCupertinoModalPopup<TrashedNote>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Papelera'),
        message: Text(
          notes.isEmpty
              ? 'La papelera está vacía.'
              : 'Elige una nota para devolverla a su carpeta.',
        ),
        actions: [
          for (final note in notes)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, note),
              child: Text(
                'Restaurar ${note.title}${note.folder == null ? '' : ' · ${note.folder}'}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ),
    );
    if (!mounted || note == null) return;
    await _editor.restoreDeletedNote(note);
    if (mounted) _editFocus.requestFocus();
  }

  Future<void> _showRecoveredDrafts() async {
    await _editor.refreshRecoveredDrafts();
    if (!mounted) return;
    if (_editor.recoveredDrafts.isEmpty) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Sin notas recuperadas'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Si un archivo externo cambia mientras tienes ediciones sin guardar, Folio conservará aquí una copia.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
      return;
    }
    final draft = await showCupertinoModalPopup<RecoveredDraft>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Notas recuperadas'),
        message: const Text(
          'Al restaurar una nota, Folio crea una copia Markdown en tu carpeta Folio.',
        ),
        actions: [
          for (final item in _editor.recoveredDrafts)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item),
              child: Text(
                'Restaurar: ${item.title} · ${item.recoveredAt.toLocal().toString().substring(0, 16)}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ),
    );
    if (!mounted || draft == null) return;
    await _editor.restoreRecovered(draft);
    _editFocus.requestFocus();
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
            onPressed: _editor.storageUnavailable
                ? _recoverStorageLocation
                : _editor.save,
            child: Text(
              _editor.storageUnavailable ? 'Elegir carpeta' : 'Reintentar',
            ),
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
                  const SizedBox(height: 8),
                  CupertinoButton(
                    onPressed: _recoverStorageLocation,
                    child: const Text('Elegir otra carpeta'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final style = FolioStyle.of(context);
      final colors = Theme.of(context).colorScheme;
      final pageContent = Column(
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
                      folderPaths: _editor.folderPaths,
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
                      onNewNoteInFolder: (folder) {
                        unawaited(_newNote(folder: folder));
                      },
                      onRenameFolder: (folder) {
                        unawaited(_renameFolder(folder));
                      },
                      onRenameNote: (note) {
                        unawaited(_renameNote(note));
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
                  child: _editor.selectedNote == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.doc_text,
                                size: 34,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              const Text('Tu espacio está listo'),
                              const SizedBox(height: 4),
                              Text(
                                'Crea una carpeta o una nota para empezar.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 14),
                              CupertinoButton.filled(
                                onPressed: _newNote,
                                child: const Text('Nueva nota'),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Container(
                              height: style.isPop ? 53 : 42,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: style.isGraphic
                                    ? colors.surfaceContainer
                                    : null,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                    width: style.isGraphic
                                        ? style.lineWidth
                                        : 1,
                                  ),
                                ),
                              ),
                              child: Text(
                                _editor.selectedNote?.title ?? 'Sin notas',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: style.isPop ? 19 : 13,
                                  fontWeight: style.isGraphic
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
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
                                                VerticalDivider(
                                                  width: style.isGraphic
                                                      ? style.lineWidth
                                                      : 1,
                                                  thickness: style.isGraphic
                                                      ? style.lineWidth
                                                      : 1,
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
                                                        const EditorPanelHeader(
                                                          title: 'VISTA PREVIA',
                                                          preview: true,
                                                        ),
                                                        Expanded(
                                                          child: ValueListenableBuilder<String>(
                                                            valueListenable: _editor
                                                                .contentListenable,
                                                            builder:
                                                                (
                                                                  context,
                                                                  content,
                                                                  _,
                                                                ) => MarkdownPreview(
                                                                  noteId: _editor
                                                                      .selectedId,
                                                                  onToggleTask:
                                                                      _toggleTask,
                                                                  readImage: _editor
                                                                      .readImage,
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
      );

      Widget framed(Widget child) => ColoredBox(
        color: colors.surface,
        child: Padding(
          padding: switch (style.kind) {
            AppStyle.retro => const EdgeInsets.fromLTRB(12, 10, 19, 17),
            AppStyle.pop => const EdgeInsets.fromLTRB(14, 12, 24, 22),
            AppStyle.clasico => EdgeInsets.zero,
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: style.isGraphic
                ? style.panel(colors.surface, lift: style.isRetro ? 6 : 9)
                : const BoxDecoration(),
            foregroundDecoration: ShapeDecoration(
              shape: style.isGraphic
                  ? style.outline
                  : const RoundedRectangleBorder(),
            ),
            child: child,
          ),
        ),
      );

      if (FolioWindowChrome.isSupported) {
        return CupertinoPageScaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              _topBar(context),
              Expanded(child: framed(pageContent)),
            ],
          ),
        );
      }

      return framed(
        CupertinoPageScaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              _topBar(context),
              Expanded(child: pageContent),
            ],
          ),
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
