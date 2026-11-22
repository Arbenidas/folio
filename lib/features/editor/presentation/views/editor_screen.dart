import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/folio_dialogs.dart';
import '../../../../core/widgets/folio_window_chrome.dart';
import '../../../../core/theme.dart';
import '../controllers/editor_notifier.dart';
import '../../domain/markdown_document.dart';
import '../../domain/note_template.dart';
import '../../domain/trashed_note.dart';
import '../../data/note_exporter.dart';
import '../../data/recovered_drafts_repository.dart';
import '../widgets/editor_pane.dart';
import '../widgets/editor_motion.dart';
import '../widgets/markdown_editing_assistant.dart';
import '../widgets/markdown_preview.dart';
import '../widgets/markdown_source_controller.dart';
import '../widgets/note_inspector_panel.dart';
import '../widgets/note_link_suggestions.dart';
import '../widgets/markdown_help.dart';
import '../widgets/notes_sidebar.dart';
import '../widgets/quick_search_dialog.dart';
import '../widgets/template_picker.dart';
import '../../../settings/presentation/views/settings_screen.dart';
import '../../../blog_publication/presentation/blog_publish_dialog.dart';
import '../../../../core/first_run_config.dart';
import '../../../../core/onboarding_preferences.dart';
import '../../../onboarding/presentation/widgets/first_run_tour.dart';
import '../../../tasks/data/desktop_widget_bridge.dart';
import '../../../tasks/data/task_repository.dart';
import '../../../tasks/domain/managed_task.dart';
import '../../../tasks/presentation/task_board_view.dart';
import '../../../tasks/presentation/task_controller.dart';
import '../../../tasks/presentation/pomodoro_control.dart';
import '../../../tasks/presentation/pomodoro_controller.dart';
import '../../../finance/presentation/controllers/finance_controller.dart';
import '../../../finance/presentation/views/finance_workspace.dart';
import '../../../finance/presentation/widgets/finance_dialogs.dart';

enum _WorkspaceMode { notes, finance }

enum _NoteView { editor, split, preview }

enum _RightPanel { none, tasks, settings, outline }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});
  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final EditorNotifier _editor;
  late final TaskController _tasks;
  late final FinanceController _finance;
  late final PomodoroController _pomodoro;
  late final DesktopWidgetBridge _widgetBridge;
  late final Listenable _workspaceChanges;
  final _text = MarkdownSourceController();
  final _editFocus = FocusNode(debugLabel: 'Editor');
  final _notesFocus = FocusNode(debugLabel: 'Notas');
  final _previewFocus = FocusNode(debugLabel: 'Vista previa');
  final _previewScroll = ScrollController();
  final _notesScroll = ScrollController();
  final _editableKey = GlobalKey<EditableTextState>();
  late final AppLifecycleListener _lifecycle;
  String? _currentId;
  _WorkspaceMode _workspaceMode = _WorkspaceMode.notes;
  bool _wasPomodoroComplete = false;
  bool _sidebar = true;
  _NoteView _noteView = _NoteView.split;
  _RightPanel _rightPanel = _RightPanel.none;
  bool _tasksExpanded = false;
  double _sidebarWidth = AnimatedNotesPanel.defaultWidth;
  double _rightPanelWidth = 356;
  String? _focusedTaskId;
  TextEditingValue? _dismissedLink;
  TextEditingValue? _highlightedLink;
  int _linkIndex = 0;
  final Set<String> _collapsedFolders = <String>{};
  double _soundVolume = 0.68;
  double? _previewTarget;
  int _scrollRevision = 0;
  Uint8List? _typingSound;
  String? _dropFolder;
  bool _syncingText = false;
  String _lastSyncedText = '';
  String _lastSearch = '';
  String _focusedPane = 'editor';
  Timer? _dropFolderTimer;

  List<_SidebarEntry> get _sidebarEntries {
    final entries = <_SidebarEntry>[];
    final folders = _editor.folderPaths;
    void appendChildren(String? parent, int depth) {
      final children =
          folders.where((path) => _parentFolder(path) == parent).toList()..sort(
            (a, b) => _folderTitle(
              a,
            ).toLowerCase().compareTo(_folderTitle(b).toLowerCase()),
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

  List<ManagedTask> get _linkedTasks =>
      _tasks.tasks.where((task) => task.noteId == _editor.selectedId).toList();

  void _openTaskBoard([ManagedTask? task]) => setState(() {
    _rightPanel = _RightPanel.tasks;
    _focusedTaskId = task?.id;
  });

  void _openTasksFromWidget(String? taskId) {
    if (!mounted) return;
    setState(() {
      _workspaceMode = _WorkspaceMode.notes;
      _rightPanel = _RightPanel.tasks;
      _tasksExpanded = false;
      _focusedTaskId = taskId;
    });
  }

  void _openFinanceFromWidget(bool openNew) {
    if (!mounted) return;
    setState(() {
      _workspaceMode = _WorkspaceMode.finance;
      if (_rightPanel != _RightPanel.settings) {
        _rightPanel = _RightPanel.none;
        _tasksExpanded = false;
      }
    });
    if (openNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          showFinanceTransactionDialog(
            context,
            controller: _finance,
            onBudgetWarning: _notifyBudgetWarning,
          ),
        );
      });
    }
  }

  void _openDailyFromWidget() {
    if (!mounted) return;
    setState(() => _workspaceMode = _WorkspaceMode.notes);
    unawaited(_openDailyNote());
  }

  void _notifyBudgetWarning(String message) {
    unawaited(
      _widgetBridge.notify(title: 'Presupuesto de Folio', body: message),
    );
  }

  void _onPomodoroChanged() {
    final complete = _pomodoro.intervalComplete;
    if (complete && !_wasPomodoroComplete) {
      unawaited(
        _widgetBridge.notify(
          title: 'Pomodoro terminado',
          body: _pomodoro.phase == PomodoroPhase.breakTime
              ? 'Buen trabajo. Es momento de tomar un descanso.'
              : 'Descanso terminado. Listo para el siguiente bloque.',
        ),
      );
    }
    _wasPomodoroComplete = complete;
  }

  Map<String, dynamic> _buildDailyWidgetPayload() {
    final now = DateTime.now();
    final dateSlug =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final dateTitle = '${now.day} ${months[now.month - 1]}';
    final matches = _editor.notes.where(
      (n) =>
          n.id == 'Diario/$dateSlug.md' ||
          (n.folder == 'Diario' && n.title == dateSlug),
    );
    if (matches.isEmpty) {
      return {'dateTitle': dateTitle, 'noteExists': false, 'items': const []};
    }
    final dailyNote = matches.first;
    final content = _editor.selectedId == dailyNote.id
        ? _text.text
        : dailyNote.content;
    final checklistRegex = RegExp(r'^\s*[-*]\s+\[([ xX])\]\s*(.+)$');
    final items = <Map<String, dynamic>>[];
    var idx = 0;
    for (final line in content.split('\n')) {
      final m = checklistRegex.firstMatch(line);
      if (m == null) continue;
      final text = m.group(2)?.trim() ?? '';
      if (text.isEmpty) continue;
      items.add({
        'id': 'daily-$idx',
        'text': text,
        'done': m.group(1) != ' ',
      });
      idx++;
      if (items.length >= 6) break;
    }
    return {'dateTitle': dateTitle, 'noteExists': true, 'items': items};
  }

  Future<void> _applyWidgetTaskToggles(List<String> taskIds) async {
    for (final id in taskIds) {
      final matches = _tasks.tasks.where((t) => t.id == id);
      if (matches.isNotEmpty && matches.first.phase != TaskPhase.done) {
        await _tasks.updatePhase(matches.first, TaskPhase.done);
      }
    }
    _syncDesktopWidget();
  }

  void _syncDesktopWidget() {
    if (!mounted || _tasks.loading) return;
    final colors = buildEditorTheme(
      AppAppearance.instance.selected,
      AppAppearance.instance.style,
    ).colorScheme;
    unawaited(
      _widgetBridge.sync(
        tasks: _tasks.tasks,
        colors: colors,
        finance: _finance.toWidgetPayload(),
        daily: _buildDailyWidgetPayload(),
      ),
    );
  }

  void _toggleTasksSidebar() {
    setState(() {
      if (_rightPanel == _RightPanel.tasks) {
        _rightPanel = _RightPanel.none;
        _tasksExpanded = false;
      } else {
        _rightPanel = _RightPanel.tasks;
        _tasksExpanded = false;
      }
    });
    if (_rightPanel == _RightPanel.none && _editor.selectedNote != null) {
      _focusEditor();
    }
  }

  void _toggleSettingsSidebar() {
    setState(() {
      _tasksExpanded = false;
      _rightPanel = _rightPanel == _RightPanel.settings
          ? _RightPanel.none
          : _RightPanel.settings;
    });
    if (_rightPanel == _RightPanel.none && _editor.selectedNote != null) {
      _focusEditor();
    }
  }

  void _toggleOutlineSidebar() {
    setState(() {
      _tasksExpanded = false;
      _rightPanel = _rightPanel == _RightPanel.outline
          ? _RightPanel.none
          : _RightPanel.outline;
    });
    if (_rightPanel == _RightPanel.none && _editor.selectedNote != null) {
      _focusEditor();
    }
  }

  void _closeRightPanel() {
    setState(() {
      _rightPanel = _RightPanel.none;
      _tasksExpanded = false;
    });
    if (_editor.selectedNote != null) _focusEditor();
  }

  void _jumpToOffset(int offset) {
    final target = offset.clamp(0, _text.text.length);
    _text.selection = TextSelection.collapsed(offset: target);
    _focusEditor();
    _revealCursor();
  }

  Future<void> _openDailyNote() async {
    final now = DateTime.now();
    final dateTitle =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    const folder = 'Diario';
    final expectedId = '$folder/$dateTitle.md';
    final existing = _editor.notes.where(
      (note) =>
          note.id == expectedId ||
          (note.folder == folder && note.title == dateTitle),
    );
    if (existing.isNotEmpty) {
      _editor.select(existing.first.id);
    } else {
      if (!_editor.folderPaths.contains(folder)) {
        await _editor.createFolder(folder);
      }
      await _editor.create(
        folder: folder,
        title: dateTitle,
        content: NoteTemplate.dailyContentFor(now),
      );
      if (mounted) {
        setState(() => _collapsedFolders.remove(folder));
      }
    }
    if (!mounted) return;
    if (_tasksExpanded) setState(() => _tasksExpanded = false);
    _focusEditor();
  }

  Future<void> _exportMarkdown() async {
    final saved = await _editor.exportMarkdown();
    if (saved && mounted) {
      await showFolioMessageDialog(
        context,
        title: 'Nota exportada',
        message: 'Tu nota se guardó correctamente como archivo Markdown (.md).',
      );
    }
  }

  Future<void> _exportHtml() async {
    final note = _editor.selectedNote;
    if (note == null) return;
    try {
      final path = await NoteExporter.exportHtml(
        note: note,
        content: _text.text,
        colors: Theme.of(context).colorScheme,
        readImage: _editor.readImage,
      );
      if (path != null && mounted) {
        await showFolioMessageDialog(
          context,
          title: 'HTML exportado',
          message: 'Se guardó «${p.basename(path)}» con tu tema actual de Folio.',
          icon: CupertinoIcons.globe,
        );
      }
    } catch (error) {
      if (mounted) _editor.reportError('No se pudo exportar a HTML: $error');
    }
  }

  Future<void> _exportPdf() async {
    final note = _editor.selectedNote;
    if (note == null) return;
    try {
      final path = await NoteExporter.exportPdf(
        note: note,
        content: _text.text,
        colors: Theme.of(context).colorScheme,
        readImage: _editor.readImage,
      );
      if (path != null && mounted) {
        await showFolioMessageDialog(
          context,
          title: 'PDF exportado',
          message: 'Se guardó «${p.basename(path)}» con tu tema y tipografía actual.',
          icon: CupertinoIcons.doc_richtext,
        );
      }
    } catch (error) {
      if (mounted) _editor.reportError('No se pudo exportar a PDF: $error');
    }
  }

  Widget _linkedTasksStrip(ColorScheme colors) {
    final tasks = _linkedTasks;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            CupertinoIcons.checkmark_circle,
            size: 15,
            color: colors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Tareas vinculadas',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 3),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final done = task.phase == TaskPhase.done;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      minimumSize: Size.zero,
                      onPressed: () => done
                          ? _tasks.reopen(task)
                          : _tasks.updatePhase(task, TaskPhase.done),
                      child: Icon(
                        done
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        size: 16,
                        color: done ? colors.primary : colors.onSurfaceVariant,
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      minimumSize: Size.zero,
                      onPressed: () => _openTaskBoard(task),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurface,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
            onPressed: _openTaskBoard,
            child: Icon(
              CupertinoIcons.square_grid_2x2,
              size: 16,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
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
    _tasks = TaskController(_taskRepository());
    _finance = FinanceController();
    _pomodoro = PomodoroController();
    _widgetBridge = DesktopWidgetBridge(
      onApplyToggles: _applyWidgetTaskToggles,
      onOpenTasks: _openTasksFromWidget,
      onOpenFinance: _openFinanceFromWidget,
      onOpenDaily: _openDailyFromWidget,
    );
    _workspaceChanges = Listenable.merge([_editor, _tasks]);
    _tasks.addListener(_syncDesktopWidget);
    _finance.addListener(_syncDesktopWidget);
    _pomodoro.addListener(_onPomodoroChanged);
    AppAppearance.instance.addListener(_syncDesktopWidget);
    unawaited(_finance.load().then((_) => _syncDesktopWidget()));
    unawaited(
      _tasks.load().then((_) async {
        await _widgetBridge.consumePendingToggles();
        _syncDesktopWidget();
      }),
    );
    _text.addListener(_onTextChanged);
    _editFocus.onKeyEvent = (node, event) {
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
      final completion = _handleNoteLinkKey(event);
      if (completion != KeyEventResult.ignored) return completion;
      final markdownAssist = MarkdownEditingAssistant.handleKey(
        _text,
        event,
        isWriting: true,
      );
      if (markdownAssist != KeyEventResult.ignored) {
        _revealCursor();
        return markdownAssist;
      }
      final isRepeat = event is KeyRepeatEvent;
      final isTypingKey =
          (event is KeyDownEvent || isRepeat) &&
          _soundVolume > 0 &&
          !keyboard.isMetaPressed &&
          !keyboard.isControlPressed;
      if (isTypingKey) {
        final key = event.logicalKey;
        String? soundKind;
        if (key == LogicalKeyboardKey.space) {
          soundKind = 'space';
        } else if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          soundKind = 'enter';
        } else if (key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) {
          soundKind = 'backspace';
        } else if (event.character != null && event.character!.isNotEmpty) {
          soundKind = 'char';
        }
        if (soundKind != null) {
          unawaited(
            const MethodChannel('apuntes/keyboard').invokeMethod<void>(
              'click',
              {'kind': soundKind, 'repeat': isRepeat},
            ).catchError((_) {}),
          );
        }
      }
      return KeyEventResult.ignored;
    };
    _editor.addListener(_sync);
    _editFocus.addListener(() {
      if (_editFocus.hasFocus) _focusedPane = 'editor';
      if (mounted) setState(() {});
    });
    _notesFocus.addListener(() {
      if (_notesFocus.hasFocus) _focusedPane = 'notes';
      if (mounted) setState(() {});
    });
    _previewFocus.addListener(() {
      if (_previewFocus.hasFocus) _focusedPane = 'preview';
      if (mounted) setState(() {});
    });
    _sync();
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_editor.save()),
      onResume: () async {
        await _editor.refresh();
        await _widgetBridge.consumePendingToggles();
        _syncDesktopWidget();
        _pomodoro.refreshAfterResume();
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
      _focusEditor();
      unawaited(_showTourIfNeeded());
    });
  }

  void _onTextChanged() {
    if (_syncingText) return;
    final current = _text.text;
    if (current == _lastSyncedText) return;
    _lastSyncedText = current;
    _editor.update(content: current);
  }

  void _restoreEditorFocus() {
    switch (_focusedPane) {
      case 'notes':
        _notesFocus.requestFocus();
      case 'preview':
        _previewFocus.requestFocus();
      default:
        _focusEditor();
    }
  }

  Future<void> _showTourIfNeeded() async {
    if (await OnboardingPreferences.tourCompleted() || !mounted) return;
    await showFirstRunTour(context);
    if (mounted) _focusEditor();
  }

  void _sync() {
    final content = _editor.selectedNote?.content ?? '';
    if (!_editor.loading &&
        !_editor.loadFailed &&
        (_currentId != _editor.selectedId || _text.text != content)) {
      _currentId = _editor.selectedId;
      _dismissedLink = null;
      _highlightedLink = null;
      _syncingText = true;
      try {
        _lastSyncedText = content;
        final clampedOffset = _text.selection.baseOffset.clamp(
          0,
          content.length,
        );
        _text.value = TextEditingValue(
          text: content,
          selection: TextSelection.collapsed(
            offset: _currentId == null ? 0 : clampedOffset,
          ),
        );
      } finally {
        _syncingText = false;
      }
    }
    _syncDesktopWidget();
  }

  TaskRepository _taskRepository([Directory? parent]) => TaskRepository(
    Directory(
      p.join((parent ?? NotesStorage.directory ?? Directory.systemTemp).path, 'Folio'),
    ),
  );

  Future<void> _openTaskNote(ManagedTask task) async {
    final matches = _editor.notes.where((item) => item.id == task.noteId);
    if (matches.isNotEmpty) {
      _editor.select(matches.first.id);
    } else {
      final title = task.noteTitle?.trim().isNotEmpty == true
          ? task.noteTitle!.trim()
          : task.title;
      final path = task.noteId;
      final slash = path?.lastIndexOf('/') ?? -1;
      final folder = slash > 0 ? path!.substring(0, slash) : null;
      final previousId = _editor.selectedId;
      await _editor.create(
        title: title,
        folder: folder != null && _editor.folderPaths.contains(folder)
            ? folder
            : null,
      );
      final created = _editor.selectedNote;
      if (created == null || created.id == previousId) return;
      await _tasks.linkNote(task, noteId: created.id, noteTitle: created.title);
    }
    if (!mounted) return;
    if (_tasksExpanded) {
      setState(() {
        _tasksExpanded = false;
      });
    }
    _focusEditor();
  }

  void _openNoteFromTaskBoard(MarkdownDocument note) {
    _editor.select(note.id);
    if (!mounted || _editor.selectedId != note.id) return;
    if (_tasksExpanded) {
      setState(() {
        _tasksExpanded = false;
      });
    }
    _focusEditor();
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
      png = await const MethodChannel(
        'folio/clipboard',
      ).invokeMethod<Uint8List>('readPng');
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
      await _editableKey.currentState?.pasteText(
        SelectionChangedCause.keyboard,
      );
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
      final offset = _text.selection.baseOffset.clamp(0, _text.text.length);
      _editableKey.currentState?.bringIntoView(TextPosition(offset: offset));
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
    _focusEditor();
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
    final previousNotes = List<MarkdownDocument>.of(_editor.notes);
    final renamed = await _editor.renameFolder(folder, title.trim());
    if (renamed != null) {
      await _tasks.relocateNotes(
        _folderNoteIdMap(folder, renamed, previousNotes),
      );
    }
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
  }) => showFolioConfirmDialog(
    context,
    title: title,
    message: message,
    actionLabel: action,
  );

  Future<void> _deleteNote(MarkdownDocument note) async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Mover nota a la papelera',
      message: 'Puedes restaurar «${note.title}» desde Archivo → Papelera.',
      action: 'Mover a la papelera',
    );
    if (!mounted || !confirmed) return;
    await _editor.deleteNote(note.id);
    _focusEditor();
  }

  Future<void> _deleteFolder(String folder) async {
    final confirmed = await _confirmDestructiveAction(
      title: 'Eliminar carpeta',
      message:
          'Se eliminará «${_folderTitle(folder)}». Sus notas y subcarpetas se conservarán en la carpeta superior.',
      action: 'Eliminar carpeta',
    );
    if (!mounted || !confirmed) return;
    final movedNoteIds = await _editor.deleteFolder(folder);
    await _tasks.relocateNotes(movedNoteIds);
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
      unawaited(_moveFolderAndRelink(data.value, destination));
    } else {
      unawaited(_moveNoteAndRelink(data.value, destination));
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
    _toggleSettingsSidebar();
  }

  Future<void> _changeNotesDirectory(Directory directory) async {
    await _editor.changeStorageDirectory(
      directory,
      beforeSwitch: () => FirstRunConfig.persistNotesDirectory(directory.path),
      copyNotebookData: (noteIds) async {
        await _tasks.flush();
        await _taskRepository().copyTo(
          Directory(p.join(directory.path, 'Folio')),
          noteIds,
        );
      },
    );
    await _tasks.changeNotebook(Directory(p.join(directory.path, 'Folio')));
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
      await _tasks.changeNotebook(Directory(p.join(path, 'Folio')));
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
  }) => showFolioPromptDialog(
    context,
    title: title,
    initial: initial,
    hint: hint,
    icon: title.toLowerCase().contains('carpeta')
        ? CupertinoIcons.folder
        : title.toLowerCase().contains('buscar')
        ? CupertinoIcons.search
        : title.toLowerCase().contains('comando')
        ? CupertinoIcons.command
        : CupertinoIcons.pencil,
  );

  Future<void> _renameNote(MarkdownDocument note) async {
    final title = await _prompt('Renombrar nota', initial: note.title);
    final name = title?.trim();
    if (!mounted || name == null || name.isEmpty || name == note.title) return;
    final renamed = await _editor.renameNote(note.id, name);
    if (renamed != null) {
      await _tasks.relocateNotes(
        {note.id: renamed.id},
        titles: {note.id: renamed.title},
      );
    }
  }

  Map<String, String> _folderNoteIdMap(
    String oldPath,
    String newPath,
    Iterable<MarkdownDocument> sourceNotes,
  ) => {
    for (final note in sourceNotes)
      if (note.id.startsWith('$oldPath/'))
        note.id: '$newPath${note.id.substring(oldPath.length)}',
  };

  Future<void> _moveNoteAndRelink(String noteId, String? folder) async {
    final previous = _editor.notes.where((note) => note.id == noteId);
    if (previous.isEmpty) return;
    final moved = await _editor.moveToFolder(noteId, folder);
    if (moved == null) return;
    await _tasks.relocateNotes(
      {noteId: moved.id},
      titles: {noteId: moved.title},
    );
  }

  Future<void> _moveFolderAndRelink(String folder, String? destination) async {
    final previousNotes = List<MarkdownDocument>.of(_editor.notes);
    final moved = await _editor.moveFolderTo(folder, destination);
    if (moved == null) return;
    await _tasks.relocateNotes(_folderNoteIdMap(folder, moved, previousNotes));
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
    if (mounted) _focusEditor();
  }

  Future<void> _search() async {
    final query = await _prompt(
      'Buscar en esta nota',
      hint: _lastSearch.isEmpty ? 'Texto a buscar' : _lastSearch,
      initial: _lastSearch,
    );
    if (!mounted) return;
    if (query != null && query.isNotEmpty) {
      _lastSearch = query;
      _findInNote(query);
    }
    _focusEditor();
    _revealCursor();
  }

  bool _findInNote(String query, {bool reverse = false}) {
    if (query.isEmpty) return false;
    final source = _text.text.toLowerCase();
    final needle = query.toLowerCase();
    if (source.isEmpty) return false;
    int match;
    if (!reverse) {
      final from = _text.selection.isValid
          ? _text.selection.end.clamp(0, source.length)
          : 0;
      match = source.indexOf(needle, from);
      if (match < 0) match = source.indexOf(needle);
    } else {
      final from = _text.selection.isValid
          ? (_text.selection.start - 1).clamp(0, source.length)
          : source.length;
      match = source.lastIndexOf(needle, from);
      if (match < 0) match = source.lastIndexOf(needle);
    }
    if (match < 0) return false;
    _text.selection = TextSelection(
      baseOffset: match,
      extentOffset: match + query.length,
    );
    _revealCursor();
    return true;
  }

  Future<void> _quickSearch({String initialQuery = ''}) async {
    final hit = await showGeneralDialog<QuickSearchHit>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar búsqueda',
      barrierColor: Colors.black38,
      transitionDuration: EditorMotion.duration(context, 150),
      pageBuilder: (_, _, _) => QuickSearchDialog(
        notes: _editor.notes,
        initialQuery: initialQuery,
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      ),
    );
    if (!mounted || hit == null) return;
    if (hit.document case final note?) {
      _editor.select(note.id);
      if (_editor.selectedId != note.id) return;
      _focusEditor();
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

  void _stepPane(int delta) {
    // Natural left ↔ right order: Sidebar ('notes') ↔ Editor ('editor') ↔ Preview ('preview')
    const panes = ['notes', 'editor', 'preview'];
    final current = panes.indexOf(_focusedPane);
    final nextIndex = ((current < 0 ? 1 : current) + delta).clamp(0, 2);
    _focusPaneByName(panes[nextIndex]);
  }

  void _cyclePane({bool reverse = false}) {
    const panes = ['notes', 'editor', 'preview'];
    final current = panes.indexOf(_focusedPane);
    final nextIndex =
        ((current < 0 ? 1 : current) + (reverse ? -1 : 1) + panes.length) %
        panes.length;
    _focusPaneByName(panes[nextIndex]);
  }

  void _focusPaneByName(String pane) {
    switch (pane) {
      case 'notes':
        _focusNotes();
      case 'preview':
        _focusPreview();
      default:
        _focusEditor();
    }
  }

  KeyEventResult _notesKey(FocusNode node, KeyEvent event) {
    final shortcut = _handleGlobalShortcut(event);
    if (shortcut != KeyEventResult.ignored) return shortcut;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.escape) {
      if (_noteView == _NoteView.preview) {
        _focusPreview();
      } else {
        _focusEditor();
      }
      return KeyEventResult.handled;
    }
    final direction = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
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
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.escape) {
      _focusEditor();
      return KeyEventResult.handled;
    }
    if (!_previewScroll.hasClients) return KeyEventResult.ignored;
    final viewport = _previewScroll.position.viewportDimension;
    double? absoluteTarget;
    double delta = 0.0;
    if (key == LogicalKeyboardKey.arrowDown) {
      delta = 72.0;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -72.0;
    } else if (key == LogicalKeyboardKey.pageDown ||
        (key == LogicalKeyboardKey.space && !shift)) {
      delta = (viewport * 0.85).clamp(180.0, 900.0);
    } else if (key == LogicalKeyboardKey.pageUp ||
        (key == LogicalKeyboardKey.space && shift)) {
      delta = -(viewport * 0.85).clamp(180.0, 900.0);
    } else if (key == LogicalKeyboardKey.home) {
      absoluteTarget = 0.0;
    } else if (key == LogicalKeyboardKey.end) {
      absoluteTarget = _previewScroll.position.maxScrollExtent;
    }
    if (absoluteTarget == null && delta == 0.0) return KeyEventResult.ignored;
    final target =
        (absoluteTarget ?? ((_previewTarget ?? _previewScroll.offset) + delta))
            .clamp(0.0, _previewScroll.position.maxScrollExtent);
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
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final shift = keyboard.isShiftPressed;
    final meta = keyboard.isMetaPressed;
    final ctrl = keyboard.isControlPressed;
    final alt = keyboard.isAltPressed;

    // Natural keyboard-only navigation across Sidebar ↔ Editor ↔ Preview:
    // ⌃← / ⌃→, ⌥⌘← / ⌥⌘→, or ⌃Tab / ⌃⇧Tab
    if (_workspaceMode == _WorkspaceMode.notes) {
      if (ctrl && !meta && !alt) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _stepPane(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _stepPane(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.tab) {
          _cyclePane(reverse: shift);
          return KeyEventResult.handled;
        }
      }
      if (meta && alt && !ctrl) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _stepPane(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _stepPane(1);
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.f1) {
      _help();
      return KeyEventResult.handled;
    }
    if (!meta) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyN && shift) {
      _newFolder();
    } else if (key == LogicalKeyboardKey.keyM && shift) {
      setState(() {
        _workspaceMode = _workspaceMode == _WorkspaceMode.notes
            ? _WorkspaceMode.finance
            : _WorkspaceMode.notes;
        if (_workspaceMode == _WorkspaceMode.finance &&
            _rightPanel != _RightPanel.settings) {
          _rightPanel = _RightPanel.none;
          _tasksExpanded = false;
        }
      });
    } else if (key == LogicalKeyboardKey.keyT && shift) {
      _toggleTasksSidebar();
    } else if (key == LogicalKeyboardKey.keyO && shift) {
      _toggleOutlineSidebar();
    } else if (key == LogicalKeyboardKey.keyF && shift) {
      AppAppearance.instance.toggleFocusMode();
    } else if (key == LogicalKeyboardKey.keyG) {
      if (_lastSearch.isNotEmpty) {
        _findInNote(_lastSearch, reverse: shift);
      } else {
        unawaited(_search());
      }
    } else if (key == LogicalKeyboardKey.keyD && !shift) {
      unawaited(_openDailyNote());
    } else if (key == LogicalKeyboardKey.keyN) {
      _newNote();
    } else if (key == LogicalKeyboardKey.keyS) {
      unawaited(_editor.save());
    } else if (key == LogicalKeyboardKey.keyK) {
      _quickSearch();
    } else if (key == LogicalKeyboardKey.keyF) {
      _search();
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      AppAppearance.instance.adjustEditorFontSize(1);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      AppAppearance.instance.adjustEditorFontSize(-1);
    } else if (key == LogicalKeyboardKey.digit0) {
      AppAppearance.instance.chooseEditorFontSize(14.5);
    } else if (key == LogicalKeyboardKey.digit1) {
      _focusNotes();
    } else if (key == LogicalKeyboardKey.digit2) {
      _focusEditor();
    } else if (key == LogicalKeyboardKey.digit3) {
      _focusPreview();
    } else if (key == LogicalKeyboardKey.digit4) {
      _toggleTasksSidebar();
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
    if (_sidebar && _notesFocus.hasFocus) _focusEditor();
    setState(() => _sidebar = !_sidebar);
  }

  void _changeNoteView(_NoteView view) {
    final focus = view == _NoteView.preview ? _previewFocus : _editFocus;
    if (_noteView == view) {
      focus.requestFocus();
      return;
    }
    setState(() => _noteView = view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _noteView == view) focus.requestFocus();
    });
  }

  void _focusEditor() => _changeNoteView(
    _noteView == _NoteView.preview ? _NoteView.split : _noteView,
  );

  void _focusPreview() {
    if (_noteView == _NoteView.editor) {
      setState(() => _noteView = _NoteView.split);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _noteView != _NoteView.editor) {
          _previewFocus.requestFocus();
        }
      });
    } else {
      _previewFocus.requestFocus();
    }
  }

  NoteLinkQuery? get _linkQuery {
    if (!_editFocus.hasFocus || _dismissedLink == _text.value) {
      return null;
    }
    return NoteLinkQuery.at(_text.value);
  }

  int _selectedLinkIndex(int count) =>
      _highlightedLink == _text.value ? _linkIndex.clamp(0, count - 1) : 0;

  KeyEventResult _handleNoteLinkKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final query = _linkQuery;
    if (query == null) return KeyEventResult.ignored;
    final notes = query.suggestions(_editor.notes, _editor.selectedId);
    if (notes.isEmpty) return KeyEventResult.ignored;
    final index = _selectedLinkIndex(notes.length);
    if (key == LogicalKeyboardKey.enter) {
      _insertNoteLink(notes[index]);
    } else if (key == LogicalKeyboardKey.escape) {
      setState(() => _dismissedLink = _text.value);
    } else {
      final direction = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _highlightedLink = _text.value;
        _linkIndex = (index + direction) % notes.length;
      });
    }
    return KeyEventResult.handled;
  }

  void _insertNoteLink(MarkdownDocument target) {
    final sourceId = _editor.selectedId;
    final query = _linkQuery;
    if (sourceId == null || query == null) return;
    final link = NoteLinkQuery.markdownLink(sourceId, target);
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(query.start, query.end, link),
      selection: TextSelection.collapsed(offset: query.start + link.length),
    );
    _revealCursor();
  }

  Widget? _noteLinkSuggestions() {
    final notes = _linkQuery?.suggestions(_editor.notes, _editor.selectedId);
    if (notes == null || notes.isEmpty) return null;
    return NoteLinkSuggestions(
      notes: notes,
      selectedIndex: _selectedLinkIndex(notes.length),
      onSelect: _insertNoteLink,
    );
  }

  void _openNoteLink(String sourceId, String href) {
    if (sourceId != _editor.selectedId) return;
    final target = NoteLinkQuery.targetId(sourceId, href);
    if (target == null || !_editor.notes.any((note) => note.id == target)) {
      return;
    }
    _editor.select(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editor.selectedId != target) return;
      if (_previewScroll.hasClients) _previewScroll.jumpTo(0);
      _previewFocus.requestFocus();
    });
  }

  Widget _noteViewSelector(ColorScheme colors) {
    final tasksActive = _rightPanel == _RightPanel.tasks;
    final pendingTasks = _tasks.tasks
        .where((task) => task.phase != TaskPhase.done)
        .length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoSlidingSegmentedControl<_NoteView>(
          groupValue: _noteView,
          backgroundColor: colors.surfaceContainerLow,
          thumbColor: colors.secondaryContainer,
          onValueChanged: (view) {
            if (view != null) _changeNoteView(view);
          },
          children: {
            for (final (view, icon, label) in const [
              (_NoteView.editor, CupertinoIcons.pencil, 'Solo editor'),
              (
                _NoteView.split,
                CupertinoIcons.square_split_2x1,
                'Vista dividida',
              ),
              (_NoteView.preview, CupertinoIcons.eye, 'Solo vista previa'),
            ])
              view: Tooltip(
                message: label,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  child: Icon(
                    icon,
                    size: 17.5,
                    color: view == _noteView
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
          },
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: tasksActive
              ? 'Ocultar panel de tareas (⌘4 / ⌘⇧T)'
              : 'Panel de tareas (⌘4 / ⌘⇧T)',
          child: CupertinoButton(
            key: const ValueKey('note-header-tasks-button'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(8),
            color: tasksActive
                ? colors.secondaryContainer
                : colors.surfaceContainerLow,
            onPressed: _toggleTasksSidebar,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.checkmark_rectangle,
                  size: 17,
                  color: tasksActive
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                if (pendingTasks > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$pendingTasks',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: tasksActive
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _notePanes(FolioStyle style) => LayoutBuilder(
    builder: (context, constraints) {
      final split = _noteView == _NoteView.split;
      final reading = _noteView == _NoteView.preview;
      final divider = style.isGraphic ? style.lineWidth : 1.0;
      final half = (constraints.maxWidth - divider) / 2;
      return Stack(
        children: [
          Positioned.fill(
            right: split ? half + divider : 0,
            child: Offstage(
              offstage: reading,
              child: ExcludeFocus(
                excluding: reading,
                child: TickerMode(
                  enabled: !reading,
                  child: ListenableBuilder(
                    listenable: _text,
                    builder: (context, _) => EditorPane(
                      controller: _text,
                      focusNode: _editFocus,
                      editableKey: _editableKey,
                      linkSuggestions: _noteLinkSuggestions(),
                      centered: _noteView == _NoteView.editor,
                      outlineActive: _rightPanel == _RightPanel.outline,
                      onToggleOutline: _toggleOutlineSidebar,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (split)
            Positioned(
              left: half,
              top: 0,
              bottom: 0,
              child: VerticalDivider(width: divider, thickness: divider),
            ),
          if (_noteView != _NoteView.editor)
            Positioned.fill(
              key: const ValueKey('note-preview'),
              left: split ? half + divider : 0,
              child: _previewPane(),
            ),
        ],
      );
    },
  );

  Widget _previewPane() => Focus(
    focusNode: _previewFocus,
    onKeyEvent: _previewKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorPanelHeader(
          title: 'VISTA PREVIA',
          preview: true,
          focused: _previewFocus.hasFocus,
        ),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _editor.contentListenable,
            builder: (context, content, _) => MarkdownPreview(
              noteId: _editor.selectedId,
              onToggleTask: _toggleTask,
              onTapLink: _openNoteLink,
              readImage: _editor.readImage,
              controller: _previewScroll,
              content: content,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _topBar(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _editor.saveStatusListenable,
        _tasks,
      ]),
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
          if (_workspaceMode == _WorkspaceMode.notes)
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
                  size: 21,
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
                    ? 14.5
                    : style.isRetro
                    ? 16
                    : 24,
                fontWeight: FontWeight.w800,
                color: toolbarForeground,
              ),
            ),
          ],
          const SizedBox(width: 14),
          _WorkspaceModeSwitcher(
            mode: _workspaceMode,
            isPop: style.isPop,
            onChanged: (next) => setState(() {
              _workspaceMode = next;
              if (next == _WorkspaceMode.finance &&
                  _rightPanel != _RightPanel.settings) {
                _rightPanel = _RightPanel.none;
                _tasksExpanded = false;
              }
            }),
          ),
          const Spacer(),
          if (_workspaceMode == _WorkspaceMode.notes) ...[
            SizedBox(
              width: 86,
              child: FadingLabel(
                _editor.saveStatus,
                style: TextStyle(fontSize: 12, color: toolbarForeground),
              ),
            ),
            PomodoroControl(controller: _pomodoro),
            const SizedBox(width: 4),
          ] else ...[
            PomodoroControl(controller: _pomodoro),
            const SizedBox(width: 4),
          ],
          _TopBarButton(
            icon: CupertinoIcons.gear_alt,
            tooltip: _rightPanel == _RightPanel.settings
                ? 'Cerrar ajustes y opciones (⌘,)'
                : 'Ajustes y opciones (⌘,)',
            active: _rightPanel == _RightPanel.settings,
            onPressed: _toggleSettingsSidebar,
          ),
        ],
      ),
    );
  }

  Future<void> _publishToBlog(MarkdownDocument clickedNote) async {
    final index = _editor.notes.indexWhere((note) => note.id == clickedNote.id);
    if (index < 0) return;
    final note = _editor.notes[index];
    final repository = _editor.repository;
    final markdown = _editor.selectedId == note.id ? _text.text : note.content;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      animationStyle: EditorMotion.dialog(context),
      builder: (_) => BlogPublishDialog(
        noteId: note.id,
        noteTitle: note.title,
        markdown: markdown,
        readImage: (path) => repository.readImage(note.id, path),
      ),
    );
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
    final note = await showFolioPickerDialog<TrashedNote>(
      context,
      title: 'Papelera',
      subtitle: notes.isEmpty
          ? 'La papelera está vacía.'
          : 'Elige una nota para devolverla a su carpeta.',
      icon: CupertinoIcons.trash,
      emptyMessage: 'No hay notas en la papelera.',
      items: [
        for (final item in notes)
          FolioPickerItem(
            value: item,
            title: item.title,
            subtitle: item.folder == null
                ? 'Carpeta principal'
                : item.folder!.replaceAll('/', '  ›  '),
            icon: CupertinoIcons.arrow_counterclockwise,
          ),
      ],
    );
    if (!mounted || note == null) return;
    final restored = await _editor.restoreDeletedNote(note);
    if (restored != null) {
      final separator = note.id.indexOf('/');
      if (separator >= 0) {
        final previousId = note.id.substring(separator + 1);
        await _tasks.relocateNotes(
          {previousId: restored.id},
          titles: {previousId: restored.title},
        );
      }
    }
    if (mounted) _focusEditor();
  }

  Future<void> _showRecoveredDrafts() async {
    await _editor.refreshRecoveredDrafts();
    if (!mounted) return;
    if (_editor.recoveredDrafts.isEmpty) {
      await showFolioMessageDialog(
        context,
        title: 'Sin notas recuperadas',
        message:
            'Si un archivo externo cambia mientras tienes ediciones sin guardar, Folio conservará aquí una copia.',
        icon: CupertinoIcons.clock,
      );
      return;
    }
    final draft = await showFolioPickerDialog<RecoveredDraft>(
      context,
      title: 'Notas recuperadas',
      subtitle:
          'Al restaurar una nota, Folio crea una copia Markdown en tu carpeta Folio.',
      icon: CupertinoIcons.clock,
      items: [
        for (final item in _editor.recoveredDrafts)
          FolioPickerItem(
            value: item,
            title: item.title,
            subtitle: item.recoveredAt.toLocal().toString().substring(0, 16),
            icon: CupertinoIcons.arrow_counterclockwise,
          ),
      ],
    );
    if (!mounted || draft == null) return;
    await _editor.restoreRecovered(draft);
    _focusEditor();
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
    _tasks.removeListener(_syncDesktopWidget);
    _finance.removeListener(_syncDesktopWidget);
    _pomodoro.removeListener(_onPomodoroChanged);
    AppAppearance.instance.removeListener(_syncDesktopWidget);
    _widgetBridge.dispose();
    _tasks.dispose();
    _finance.dispose();
    _pomodoro.dispose();
    _text.removeListener(_onTextChanged);
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
    listenable: _workspaceChanges,
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
      final activeNote = _editor.selectedNote;
      final showFullTaskBoard =
          _rightPanel == _RightPanel.tasks && _tasksExpanded;
      final showRightSidebar =
          (_rightPanel == _RightPanel.tasks && !_tasksExpanded) ||
          _rightPanel == _RightPanel.settings ||
          _rightPanel == _RightPanel.outline;

      final Widget centerWorkspace = showFullTaskBoard
          ? TaskBoardView(
              controller: _tasks,
              notes: _editor.notes,
              activeNote: activeNote,
              isSidebar: false,
              onToggleExpand: () => setState(() => _tasksExpanded = false),
              onOpenNote: _openNoteFromTaskBoard,
              onCreateNote: _openTaskNote,
              onBackToNotes: _closeRightPanel,
              focusTaskId: _focusedTaskId,
            )
          : activeNote == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.doc_text,
                    size: 34,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text('Tu espacio está listo'),
                  const SizedBox(height: 4),
                  Text(
                    'Crea una carpeta o una nota para empezar.',
                    style: TextStyle(color: colors.onSurfaceVariant),
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
                  height: style.isPop ? 56 : 46,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: style.isGraphic ? colors.surfaceContainer : null,
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant,
                        width: style.isGraphic ? style.lineWidth : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FadingLabel(
                          activeNote.title,
                          style: TextStyle(
                            fontSize: style.isPop ? 20 : 16.5,
                            fontWeight: style.isGraphic
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _noteViewSelector(colors),
                    ],
                  ),
                ),
                if (_linkedTasks.isNotEmpty) _linkedTasksStrip(colors),
                Expanded(child: _notePanes(style)),
              ],
            );

      final Widget rightSidebarChild = switch (_rightPanel) {
        _RightPanel.settings => SettingsScreen(
          key: const ValueKey('settings-sidebar'),
          embedded: true,
          onClose: _closeRightPanel,
          initialVolume: _soundVolume,
          onVolumeChanged: (value) => setState(() => _soundVolume = value),
          initialNotesDirectory:
              NotesStorage.directory ?? Directory.systemTemp,
          onNotesDirectoryChanged: _changeNotesDirectory,
          quickActions: SettingsQuickActions(
            onSearch: () => unawaited(_quickSearch()),
            onDailyNote: () => unawaited(_openDailyNote()),
            onTemplates: () => unawaited(_newFromTemplate()),
            onOpenOutline: _toggleOutlineSidebar,
            onImportMarkdown: () => unawaited(_editor.importMarkdown()),
            onExportMarkdown: () => unawaited(_exportMarkdown()),
            onExportHtml: () => unawaited(_exportHtml()),
            onExportPdf: () => unawaited(_exportPdf()),
            onRecoveredDrafts: () => unawaited(_showRecoveredDrafts()),
            recoveredCount: _editor.recoveredDrafts.length,
            onTrash: () => unawaited(_showTrash()),
            onHelp: () => unawaited(_help()),
          ),
        ),
        _RightPanel.outline => ValueListenableBuilder<String>(
          key: const ValueKey('outline-sidebar'),
          valueListenable: _editor.contentListenable,
          builder: (context, content, _) => NoteInspectorPanel(
            note: activeNote,
            content: content,
            allNotes: _editor.notes,
            onJumpToOffset: _jumpToOffset,
            onOpenNote: (note) {
              _editor.select(note.id);
              _focusEditor();
            },
            onSearchTag: (tag) => unawaited(_quickSearch(initialQuery: tag)),
            onClose: _closeRightPanel,
          ),
        ),
        _ => TaskBoardView(
          key: const ValueKey('tasks-sidebar'),
          controller: _tasks,
          notes: _editor.notes,
          activeNote: activeNote,
          isSidebar: true,
          onToggleExpand: () => setState(() => _tasksExpanded = true),
          onOpenNote: _openNoteFromTaskBoard,
          onCreateNote: _openTaskNote,
          onBackToNotes: _closeRightPanel,
          focusTaskId: _focusedTaskId,
        ),
      };

      final Widget pageContent = _workspaceMode == _WorkspaceMode.finance
          ? Row(
              children: [
                Expanded(
                  child: FinanceWorkspace(
                    controller: _finance,
                    onBudgetWarning: _notifyBudgetWarning,
                  ),
                ),
                AnimatedRightPanel(
                  visible: _rightPanel == _RightPanel.settings,
                  width: _rightPanelWidth,
                  onResizeDelta: (delta) => setState(() {
                    _rightPanelWidth = (_rightPanelWidth + delta).clamp(
                      290.0,
                      520.0,
                    );
                  }),
                  child: rightSidebarChild,
                ),
              ],
            )
          : Column(
        children: [
          if (_editor.error != null) _errorBanner(context),
          Expanded(
            child: Row(
              children: [
                AnimatedNotesPanel(
                  visible: _sidebar,
                  width: _sidebarWidth,
                  onResizeDelta: (delta) => setState(() {
                    _sidebarWidth = (_sidebarWidth + delta).clamp(220.0, 380.0);
                  }),
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
                    onPublishNote: (note) {
                      unawaited(_publishToBlog(note));
                    },
                    onDeleteFolder: (folder) {
                      unawaited(_deleteFolder(folder));
                    },
                    onDeleteNote: (note) {
                      unawaited(_deleteNote(note));
                    },
                    onSelectNote: (note) {
                      _editor.select(note.id);
                      if (_noteView == _NoteView.preview) {
                        _focusPreview();
                      } else {
                        _focusEditor();
                      }
                    },
                    onToggleFolder: (folder) => setState(() {
                      if (!_collapsedFolders.add(folder)) {
                        _collapsedFolders.remove(folder);
                      }
                    }),
                    canDropIntoFolder: _canDropIntoFolder,
                    onDropIntoFolder: _moveIntoFolder,
                    inProgressTasks: _tasks.tasks
                        .where((task) => task.phase == TaskPhase.inProgress)
                        .toList(),
                    taskCount: _tasks.tasks
                        .where((task) => task.phase == TaskPhase.inProgress)
                        .length,
                    onOpenTasks: () => setState(() {
                      _rightPanel = _RightPanel.tasks;
                      _tasksExpanded = false;
                    }),
                    onOpenTaskNote: (task) => unawaited(_openTaskNote(task)),
                    onOpenDailyNote: () => unawaited(_openDailyNote()),
                    onQuickSearch: () => unawaited(_quickSearch()),
                  ),
                ),
                Expanded(child: centerWorkspace),
                AnimatedRightPanel(
                  visible: showRightSidebar,
                  width: _rightPanelWidth,
                  onResizeDelta: (delta) => setState(() {
                    _rightPanelWidth = (_rightPanelWidth + delta).clamp(
                      290.0,
                      520.0,
                    );
                  }),
                  child: AnimatedSwitcher(
                    duration: EditorMotion.duration(context, 160),
                    switchInCurve: EditorMotion.curve,
                    switchOutCurve: EditorMotion.reverseCurve,
                    child: rightSidebarChild,
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

class _WorkspaceModeSwitcher extends StatelessWidget {
  const _WorkspaceModeSwitcher({
    required this.mode,
    required this.onChanged,
    this.isPop = false,
  });

  final _WorkspaceMode mode;
  final ValueChanged<_WorkspaceMode> onChanged;
  final bool isPop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Cambiar entre Notas y Finanzas (⌘⇧M)',
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: isPop
              ? colors.surface.withValues(alpha: 0.85)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              context,
              icon: CupertinoIcons.doc_text,
              label: 'Notas',
              selected: mode == _WorkspaceMode.notes,
              onTap: () => onChanged(_WorkspaceMode.notes),
            ),
            const SizedBox(width: 2),
            _pill(
              context,
              icon: CupertinoIcons.chart_pie,
              label: 'Finanzas',
              selected: mode == _WorkspaceMode.finance,
              onTap: () => onChanged(_WorkspaceMode.finance),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13.5,
              color: selected
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => MacosTooltip(
    message: tooltip,
    child: AppIconButton(
      semanticLabel: tooltip,
      onPressed: onPressed,
      icon: icon,
      size: 20.5,
      active: active,
      badgeCount: badgeCount,
    ),
  );
}
