import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/folio_dialogs.dart';
import '../cloud_sync/data/folio_cloud_sync_service.dart';
import '../editor/presentation/widgets/preview_code_block.dart';
import '../finance/domain/finance_models.dart';
import '../onboarding/presentation/widgets/section_tour_card.dart';

class CloudNoteFolder {
  const CloudNoteFolder({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  CloudNoteFolder copyWith({String? name}) =>
      CloudNoteFolder(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory CloudNoteFolder.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return CloudNoteFolder(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Carpeta',
    );
  }
}

class CloudNoteItem {
  const CloudNoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAtMs,
    this.folderId,
  });

  final String id;
  final String title;
  final String content;
  final int updatedAtMs;
  final String? folderId;

  CloudNoteItem copyWith({
    String? title,
    String? content,
    int? updatedAtMs,
    String? folderId,
    bool clearFolder = false,
  }) => CloudNoteItem(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    folderId: clearFolder ? null : (folderId ?? this.folderId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'updatedAtMs': updatedAtMs,
    'folderId': ?folderId,
  };

  factory CloudNoteItem.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return CloudNoteItem(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Sin título',
      content: map['content'] as String? ?? '',
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
      folderId: map['folderId'] as String?,
    );
  }
}

/// Full folder-and-note Markdown workspace for Web & Mobile with local
/// SharedPreferences storage, real-time Firestore sync, and an interactive
/// 3-step section tour.
class CrossPlatformNotesWorkspace extends StatefulWidget {
  const CrossPlatformNotesWorkspace({
    super.key,
    this.enableSectionTour = false,
    this.replayTourTrigger,
  });

  final bool enableSectionTour;
  final ValueListenable<int>? replayTourTrigger;

  @override
  State<CrossPlatformNotesWorkspace> createState() =>
      _CrossPlatformNotesWorkspaceState();
}

class _CrossPlatformNotesWorkspaceState
    extends State<CrossPlatformNotesWorkspace> {
  static const _storageKey = 'folio_web_mobile_notebook_v1';
  static const _legacyScratchKey = 'folio_web_mobile_scratchpad_v1';
  static const _tourDoneKey = 'folio_tour_notes_done_v1';
  static const _envelopeFormat = 'folio_notebook_v1';

  final GlobalKey _keyNewFolderBtn = GlobalKey();
  final GlobalKey _keyFoldersList = GlobalKey();
  final GlobalKey _keyNewNoteBtn = GlobalKey();
  final GlobalKey _keyPreviewToggle = GlobalKey();

  late final List<SectionTourStep> _tourSteps = <SectionTourStep>[
    SectionTourStep(
      badge: 'NOTAS · NUEVA CARPETA',
      title: 'Crea carpetas para organizarte',
      description:
          'Toca este botón para crear carpetas (Trabajo, Estudio, Ideas…) y separar tus apuntes sin mezclar temas.',
      icon: Icons.create_new_folder_rounded,
      targetKey: _keyNewFolderBtn,
      borderRadius: 10,
    ),
    SectionTourStep(
      badge: 'NOTAS · CARPETAS',
      title: 'Filtra por carpeta o busca',
      description:
          'Toca cualquier carpeta para filtrar tus notas. También puedes renombrar o eliminar carpetas desde el menú ⋯.',
      icon: Icons.folder_copy_rounded,
      targetKey: _keyFoldersList,
      borderRadius: 12,
    ),
    SectionTourStep(
      badge: 'NOTAS · NUEVA NOTA',
      title: 'Agrega notas en 1 clic',
      description:
          'Crea una nueva nota Markdown dentro de la carpeta que tengas seleccionada. Se guarda automáticamente al escribir.',
      icon: Icons.note_add_rounded,
      targetKey: _keyNewNoteBtn,
      borderRadius: 10,
    ),
    SectionTourStep(
      badge: 'NOTAS · VISTA PREVIA',
      title: 'Alterna entre Editar y Vista',
      description:
          'Cambia aquí para leer tu nota Markdown formateada. Al iniciar sesión en Ajustes, tus carpetas se sincronizan en la nube.',
      icon: Icons.visibility_rounded,
      targetKey: _keyPreviewToggle,
      borderRadius: 10,
    ),
  ];

  final Random _random = Random.secure();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  List<CloudNoteFolder> _folders = [];
  List<CloudNoteItem> _notes = [];
  String? _selectedFolderId; // Used as default target when creating a new note
  final Set<String> _collapsedFolders = {};
  String? _selectedNoteId;
  bool _previewMode = false;
  bool _mobileSidebarOpen = false;
  bool _loading = true;

  // Interactive section tour state
  bool _showTour = false;
  int _tourStep = 0;

  // Cloud sync state
  StreamSubscription<RemoteScratchpadPayload?>? _cloudSub;
  Timer? _cloudDebounce;
  int _lastUpdatedMs = 0;

  @override
  void initState() {
    super.initState();
    FolioCloudSyncService.instance.addListener(_onAuthChanged);
    widget.replayTourTrigger?.addListener(_restartTour);
    unawaited(_loadNotebook());
    if (widget.enableSectionTour) {
      unawaited(_maybeStartTour());
    }
  }

  @override
  void didUpdateWidget(covariant CrossPlatformNotesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replayTourTrigger != widget.replayTourTrigger) {
      oldWidget.replayTourTrigger?.removeListener(_restartTour);
      widget.replayTourTrigger?.addListener(_restartTour);
    }
  }

  @override
  void dispose() {
    _cloudDebounce?.cancel();
    _cloudSub?.cancel();
    FolioCloudSyncService.instance.removeListener(_onAuthChanged);
    widget.replayTourTrigger?.removeListener(_restartTour);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';

  Future<void> _maybeStartTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_tourDoneKey) ?? false;
      if (!done && mounted) {
        setState(() {
          _showTour = true;
          _tourStep = 0;
          _previewMode = false;
          _mobileSidebarOpen = true;
        });
      }
    } catch (_) {}
  }

  void _restartTour() {
    if (!mounted) return;
    setState(() {
      _showTour = true;
      _tourStep = 0;
      _previewMode = false;
      _mobileSidebarOpen = true;
    });
  }

  Future<void> _finishTour() async {
    setState(() => _showTour = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tourDoneKey, true);
    } catch (_) {}
  }

  void _goToTourStep(int step) {
    setState(() {
      _tourStep = step;
      // Show sidebar on folder/note creation steps (0, 1, 2), editor + preview on step 3!
      if (step <= 2) {
        _previewMode = false;
        _mobileSidebarOpen = true;
      } else {
        _previewMode = true;
        _mobileSidebarOpen = false;
      }
    });
  }

  void _seedStarter({String? legacyText}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _folders = const [
      CloudNoteFolder(id: 'fld-personal', name: 'Personal'),
      CloudNoteFolder(id: 'fld-work', name: 'Proyectos'),
    ];
    _notes = [
      CloudNoteItem(
        id: 'note-welcome',
        title: 'Bienvenida a tus notas',
        folderId: 'fld-personal',
        updatedAtMs: now,
        content:
            legacyText ??
            '# Bienvenida a Folio Notas\n\nOrganiza tus ideas con **carpetas** desde la barra lateral izquierda.\n\n## Prueba rápida\n- [x] Crear carpetas para separar temas\n- [ ] Escribir notas en Markdown con vista previa\n- [ ] Iniciar sesión en **Ajustes** para sincronizar en la nube\n',
      ),
      CloudNoteItem(
        id: 'note-ideas',
        title: 'Lista de ideas',
        folderId: 'fld-work',
        updatedAtMs: now - 1000,
        content:
            '# Ideas y pendientes\n\n- Meta del mes\n- Próximos pasos del proyecto\n',
      ),
    ];
    _selectNote(_notes.first);
  }

  Future<void> _loadNotebook() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        _applyDecodedEnvelope(raw);
      } else {
        final legacy = prefs.getString(_legacyScratchKey);
        _seedStarter(legacyText: legacy);
        await _persistLocalOnly();
      }
    } catch (_) {
      _seedStarter();
    }
    if (mounted) {
      setState(() => _loading = false);
      _onAuthChanged();
    }
  }

  bool _applyDecodedEnvelope(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['format'] == _envelopeFormat) {
        final folders = [
          for (final f in (decoded['folders'] as List<dynamic>? ?? const []))
            CloudNoteFolder.fromJson(f),
        ];
        final notes = [
          for (final n in (decoded['notes'] as List<dynamic>? ?? const []))
            CloudNoteItem.fromJson(n),
        ];
        _folders = folders;
        _notes = notes;
        if (_selectedFolderId != null &&
            !_folders.any((f) => f.id == _selectedFolderId)) {
          _selectedFolderId = null;
        }
        if (_notes.isNotEmpty) {
          final current = _notes
              .where((n) => n.id == _selectedNoteId)
              .firstOrNull;
          _selectNote(current ?? _notes.first);
        } else {
          _selectedNoteId = null;
          _titleCtrl.clear();
          _bodyCtrl.clear();
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  String _encodeEnvelope() => jsonEncode({
    'format': _envelopeFormat,
    'folders': [for (final f in _folders) f.toJson()],
    'notes': [for (final n in _notes) n.toJson()],
  });

  Future<void> _persistLocalOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _encodeEnvelope());
    } catch (_) {}
  }

  void _commitChanges() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _lastUpdatedMs = ts;
    unawaited(_persistLocalOnly());
    if (FolioCloudSyncService.instance.isSignedIn) {
      final serialized = _encodeEnvelope();
      _cloudDebounce?.cancel();
      _cloudDebounce = Timer(const Duration(milliseconds: 550), () {
        unawaited(
          FolioCloudSyncService.instance.uploadScratchpad(
            serialized,
            updatedAtMs: ts,
          ),
        );
      });
    }
  }

  void _onAuthChanged() {
    final sync = FolioCloudSyncService.instance;
    if (!sync.isSignedIn) {
      _cloudSub?.cancel();
      _cloudSub = null;
      return;
    }
    _cloudSub ??= sync.watchScratchpad().listen((remote) {
      if (remote == null || remote.updatedAtMs <= _lastUpdatedMs) return;
      _lastUpdatedMs = remote.updatedAtMs;
      if (_applyDecodedEnvelope(remote.content)) {
        unawaited(_persistLocalOnly());
        if (mounted) setState(() {});
      }
    });
  }

  CloudNoteItem? get _activeNote {
    for (final n in _notes) {
      if (n.id == _selectedNoteId) return n;
    }
    return null;
  }

  void _selectNote(CloudNoteItem note) {
    _selectedNoteId = note.id;
    _titleCtrl.text = note.title;
    _bodyCtrl.text = note.content;
  }

  Future<void> _createFolder() async {
    final name = await showFolioPromptDialog(
      context,
      title: 'Nueva carpeta',
      hint: 'Ej. Estudio, Trabajo, Finanzas…',
      confirmLabel: 'Crear',
      icon: Icons.create_new_folder_rounded,
    );
    if (name == null || name.trim().isEmpty) return;
    final folder = CloudNoteFolder(id: _nextId('fld'), name: name.trim());
    setState(() {
      _folders = [..._folders, folder];
      _selectedFolderId = folder.id;
    });
    _commitChanges();
  }

  Future<void> _renameFolder(CloudNoteFolder folder) async {
    final next = await showFolioPromptDialog(
      context,
      title: 'Renombrar carpeta',
      initial: folder.name,
      confirmLabel: 'Guardar',
      icon: Icons.drive_file_rename_outline_rounded,
    );
    if (next == null || next.trim().isEmpty) return;
    setState(() {
      _folders = [
        for (final f in _folders)
          f.id == folder.id ? f.copyWith(name: next.trim()) : f,
      ];
    });
    _commitChanges();
  }

  void _deleteFolder(CloudNoteFolder folder) {
    setState(() {
      _folders = _folders.where((f) => f.id != folder.id).toList();
      _notes = [
        for (final n in _notes)
          n.folderId == folder.id ? n.copyWith(clearFolder: true) : n,
      ];
      if (_selectedFolderId == folder.id) _selectedFolderId = null;
    });
    _commitChanges();
  }

  void _createNote({String? inFolderId}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final folderId =
        inFolderId ??
        (_selectedFolderId == '__unfiled__' ? null : _selectedFolderId);
    final note = CloudNoteItem(
      id: _nextId('note'),
      title: 'Nueva nota',
      content: '# Nueva nota\n\n',
      folderId: folderId,
      updatedAtMs: now,
    );
    setState(() {
      if (folderId != null) {
        _collapsedFolders.remove(folderId);
        _selectedFolderId = folderId;
      }
      _notes = [note, ..._notes];
      _selectNote(note);
      _previewMode = false;
      _mobileSidebarOpen = false;
    });
    _commitChanges();
  }

  void _deleteNoteById(String noteId) {
    setState(() {
      _notes = _notes.where((n) => n.id != noteId).toList();
      if (_selectedNoteId == noteId) {
        if (_notes.isNotEmpty) {
          _selectNote(_notes.first);
        } else {
          _selectedNoteId = null;
          _titleCtrl.clear();
          _bodyCtrl.clear();
        }
      }
    });
    _commitChanges();
  }

  Future<void> _renameNoteById(CloudNoteItem note) async {
    final next = await showFolioPromptDialog(
      context,
      title: 'Renombrar nota',
      initial: note.title,
      confirmLabel: 'Guardar',
      icon: Icons.edit_note_rounded,
    );
    if (next == null || next.trim().isEmpty) return;
    final trimmed = next.trim();
    setState(() {
      _notes = [
        for (final n in _notes)
          n.id == note.id
              ? n.copyWith(
                  title: trimmed,
                  updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                )
              : n,
      ];
      if (_selectedNoteId == note.id) {
        _titleCtrl.text = trimmed;
      }
    });
    _commitChanges();
  }

  void _toggleFolderCollapsed(String folderId) {
    setState(() {
      if (_collapsedFolders.contains(folderId)) {
        _collapsedFolders.remove(folderId);
      } else {
        _collapsedFolders.add(folderId);
      }
      _selectedFolderId = folderId;
    });
  }

  void _updateActiveNote({String? title, String? content, String? folderId, bool clearFolder = false}) {
    final active = _activeNote;
    if (active == null) return;
    final updated = active.copyWith(
      title: title,
      content: content,
      folderId: folderId,
      clearFolder: clearFolder,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _notes = [
        for (final n in _notes) n.id == active.id ? updated : n,
      ];
    });
    _commitChanges();
  }

  void _deleteActiveNote() {
    final active = _activeNote;
    if (active == null) return;
    _deleteNoteById(active.id);
  }

  int _noteCountInFolder(String? folderId) {
    if (folderId == null) return _notes.length;
    if (folderId == '__unfiled__') {
      return _notes.where((n) => n.folderId == null).length;
    }
    return _notes.where((n) => n.folderId == folderId).length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);

    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 740;
        final sidebar = _buildSidebar(colors, palette, compact: compact);
        final editor = _buildEditorArea(colors, palette, compact: compact);

        return Stack(
          children: [
            if (compact)
              _mobileSidebarOpen ? sidebar : editor
            else
              Row(
                children: [
                  SizedBox(width: 274, child: sidebar),
                  VerticalDivider(width: 1, thickness: 1, color: palette.border),
                  Expanded(child: editor),
                ],
              ),
            if (_showTour)
              Positioned.fill(
                child: SpotlightTourOverlay(
                  steps: _tourSteps,
                  currentIndex: _tourStep,
                  onSkip: () => unawaited(_finishTour()),
                  onBack: () {
                    if (_tourStep > 0) _goToTourStep(_tourStep - 1);
                  },
                  onNext: () {
                    if (_tourStep + 1 < _tourSteps.length) {
                      _goToTourStep(_tourStep + 1);
                    } else {
                      unawaited(_finishTour());
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar(
    ColorScheme colors,
    FinancePalette palette, {
    required bool compact,
  }) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final isSearching = query.isNotEmpty;
    final sortedFolders = [..._folders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final rootNotes = _notes.where((n) => n.folderId == null).toList();
    final matchingNotes = isSearching
        ? _notes
              .where(
                (n) =>
                    n.title.toLowerCase().contains(query) ||
                    n.content.toLowerCase().contains(query),
              )
              .toList()
        : const <CloudNoteItem>[];

    return Container(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Desktop-matched top bar: NOTAS [count]  [New folder] [New note]
          Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'NOTAS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_notes.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                _SidebarIconButton(
                  key: _keyNewFolderBtn,
                  icon: CupertinoIcons.folder_badge_plus,
                  tooltip: 'Nueva carpeta',
                  onPressed: () => unawaited(_createFolder()),
                ),
                const SizedBox(width: 2),
                _SidebarIconButton(
                  key: _keyNewNoteBtn,
                  icon: CupertinoIcons.plus,
                  tooltip: 'Nueva nota',
                  onPressed: () => _createNote(),
                ),
              ],
            ),
          ),

          // Compact search field
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Buscar notas…',
              style: TextStyle(fontSize: 13, color: colors.onSurface),
              placeholderStyle: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant.withValues(alpha: 0.72),
              ),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Natural collapsible folder tree (like macOS desktop)
          Expanded(
            key: _keyFoldersList,
            child: isSearching
                ? (matchingNotes.isEmpty
                      ? Center(
                          child: Text(
                            'Sin resultados para «${_searchCtrl.text.trim()}»',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 88),
                          itemCount: matchingNotes.length,
                          itemBuilder: (context, index) {
                            final note = matchingNotes[index];
                            final folderName = _folders
                                .where((f) => f.id == note.folderId)
                                .firstOrNull
                                ?.name;
                            return _TreeNoteRow(
                              note: note,
                              subtitle: folderName,
                              indented: false,
                              selected: note.id == _selectedNoteId,
                              onTap: () {
                                setState(() {
                                  _selectNote(note);
                                  if (compact) _mobileSidebarOpen = false;
                                });
                              },
                              onRename: () => unawaited(_renameNoteById(note)),
                              onDelete: () => _deleteNoteById(note.id),
                            );
                          },
                        ))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 88),
                    children: [
                      for (final folder in sortedFolders) ...[
                        _TreeFolderRow(
                          label: folder.name,
                          count: _noteCountInFolder(folder.id),
                          expanded: !_collapsedFolders.contains(folder.id),
                          selected: _selectedFolderId == folder.id,
                          onToggle: () => _toggleFolderCollapsed(folder.id),
                          onNewNoteInside: () =>
                              _createNote(inFolderId: folder.id),
                          onRename: () => unawaited(_renameFolder(folder)),
                          onDelete: () => _deleteFolder(folder),
                        ),
                        if (!_collapsedFolders.contains(folder.id)) ...[
                          for (final note
                              in _notes.where((n) => n.folderId == folder.id))
                            _TreeNoteRow(
                              note: note,
                              indented: true,
                              selected: note.id == _selectedNoteId,
                              onTap: () {
                                setState(() {
                                  _selectedFolderId = folder.id;
                                  _selectNote(note);
                                  if (compact) _mobileSidebarOpen = false;
                                });
                              },
                              onRename: () => unawaited(_renameNoteById(note)),
                              onDelete: () => _deleteNoteById(note.id),
                            ),
                        ],
                      ],
                      if (rootNotes.isNotEmpty) ...[
                        if (sortedFolders.isNotEmpty) const SizedBox(height: 6),
                        for (final note in rootNotes)
                          _TreeNoteRow(
                            note: note,
                            indented: false,
                            selected: note.id == _selectedNoteId,
                            onTap: () {
                              setState(() {
                                _selectedFolderId = null;
                                _selectNote(note);
                                if (compact) _mobileSidebarOpen = false;
                              });
                            },
                            onRename: () => unawaited(_renameNoteById(note)),
                            onDelete: () => _deleteNoteById(note.id),
                          ),
                      ],
                      if (sortedFolders.isEmpty && rootNotes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 32,
                            horizontal: 12,
                          ),
                          child: Text(
                            'Sin notas todavía.\nPulsa + para crear tu primera nota.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorArea(
    ColorScheme colors,
    FinancePalette palette, {
    required bool compact,
  }) {
    final active = _activeNote;
    if (active == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 40,
              color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            Text(
              'Crea o selecciona una nota',
              style: TextStyle(fontSize: 14.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              borderRadius: BorderRadius.circular(10),
              onPressed: _createNote,
              child: const Text('+ Nueva nota'),
            ),
          ],
        ),
      );
    }

    final folderName =
        _folders.where((f) => f.id == active.folderId).firstOrNull?.name ??
        'Sin carpeta';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Note Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              if (compact) ...[
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  minimumSize: Size.zero,
                  color: palette.cardBg,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => setState(() => _mobileSidebarOpen = true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Carpetas',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: PopupMenuButton<String>(
                  tooltip: 'Mover a carpeta',
                  onSelected: (val) {
                    if (val == '__none__') {
                      _updateActiveNote(clearFolder: true);
                    } else {
                      _updateActiveNote(folderId: val);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: '__none__',
                      child: Text('Sin carpeta'),
                    ),
                    for (final f in _folders)
                      PopupMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          folderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              CupertinoSlidingSegmentedControl<bool>(
                key: _keyPreviewToggle,
                groupValue: _previewMode,
                onValueChanged: (v) {
                  if (v != null) setState(() => _previewMode = v);
                },
                children: const {
                  false: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    child: Text('Editar', style: TextStyle(fontSize: 11.5)),
                  ),
                  true: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    child: Text('Vista', style: TextStyle(fontSize: 11.5)),
                  ),
                },
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Eliminar nota',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  onPressed: _deleteActiveNote,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Title + Markdown editor / preview
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      onChanged: (v) => _updateActiveNote(title: v),
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Título de la nota…',
                        hintStyle: TextStyle(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Divider(height: 12, color: palette.border),
                    Expanded(
                      child: _previewMode
                          ? Markdown(
                              data: _bodyCtrl.text,
                              selectable: true,
                              padding: const EdgeInsets.only(bottom: 100),
                              builders: {'pre': PreviewCodeBlock()},
                              styleSheet: MarkdownStyleSheet.fromTheme(
                                Theme.of(context),
                              ).copyWith(
                                codeblockDecoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            )
                          : TextField(
                              controller: _bodyCtrl,
                              maxLines: null,
                              expands: true,
                              onChanged: (v) => _updateActiveNote(content: v),
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.58,
                                color: colors.onSurface,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Escribe tu nota en Markdown…',
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarIconButton extends StatefulWidget {
  const _SidebarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<_SidebarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered
                  ? colors.surfaceContainerHighest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: _hovered ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeFolderRow extends StatefulWidget {
  const _TreeFolderRow({
    required this.label,
    required this.count,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onNewNoteInside,
    required this.onRename,
    required this.onDelete,
  });

  final String label;
  final int count;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onNewNoteInside;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_TreeFolderRow> createState() => _TreeFolderRowState();
}

class _TreeFolderRowState extends State<_TreeFolderRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.surfaceContainerHighest.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: widget.expanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                widget.expanded
                    ? CupertinoIcons.folder_open
                    : CupertinoIcons.folder,
                size: 15,
                color: widget.selected
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (!_hovered)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 150,
                  ),
                  tooltip: 'Opciones de carpeta',
                  onSelected: (v) {
                    if (v == 'new_note') widget.onNewNoteInside();
                    if (v == 'rename') widget.onRename();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'new_note',
                      child: Text('Nueva nota aquí'),
                    ),
                    PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 16,
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

class _TreeNoteRow extends StatefulWidget {
  const _TreeNoteRow({
    required this.note,
    required this.indented,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.subtitle,
  });

  final CloudNoteItem note;
  final bool indented;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final String? subtitle;

  @override
  State<_TreeNoteRow> createState() => _TreeNoteRowState();
}

class _TreeNoteRowState extends State<_TreeNoteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = widget.selected
        ? colors.secondaryContainer.withValues(alpha: 0.92)
        : _hovered
        ? colors.surfaceContainerHighest.withValues(alpha: 0.62)
        : Colors.transparent;

    return Padding(
      padding: EdgeInsets.only(left: widget.indented ? 18 : 0, bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(9, 6.5, 4, 6.5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.doc_text,
                  size: 14,
                  color: widget.selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.note.title.isEmpty
                            ? 'Sin título'
                            : widget.note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: widget.selected
                              ? colors.onSecondaryContainer
                              : colors.onSurface,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_hovered || widget.selected)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: 'Opciones de nota',
                    onSelected: (v) {
                      if (v == 'rename') widget.onRename();
                      if (v == 'delete') widget.onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 15,
                        color: widget.selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
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
}
