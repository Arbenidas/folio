import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/first_run_config.dart';
import '../../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../../data/desktop_notes_cloud_sync.dart';
import '../../data/file_repository.dart';
import '../../data/notebook_sync_service.dart';
import '../../data/recovered_drafts_repository.dart';
import '../../domain/document_repository.dart';
import '../../domain/markdown_document.dart';
import '../../domain/notebook_snapshot.dart';
import '../../domain/trashed_note.dart';

final editorProvider = Provider<EditorNotifier>((ref) {
  final editor = EditorNotifier(
    FileRepository(directory: NotesStorage.directory),
  );
  ref.onDispose(editor.dispose);
  unawaited(editor.load());
  return editor;
});

class EditorNotifier extends ChangeNotifier {
  EditorNotifier(this.repository, {RecoveredDraftsRepository? recovered})
    : recoveredRepository = recovered ?? RecoveredDraftsRepository();

  DocumentRepository repository;
  final RecoveredDraftsRepository recoveredRepository;
  List<MarkdownDocument> notes = [];
  Set<String> folderPaths = {};
  List<RecoveredDraft> recoveredDrafts = [];
  String? selectedId;
  bool loading = true;
  bool loadFailed = false;
  bool importing = false;
  bool syncing = false;
  bool storageUnavailable = false;
  String? error;
  String saveStatus = 'Cargando…';
  final contentListenable = ValueNotifier<String>('');
  final saveStatusListenable = ValueNotifier<String>('Cargando…');
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void> _reconciliations = Future.value();
  int _revision = 0;
  bool _disposed = false;
  NotebookSyncService? _sync;
  StreamSubscription<NotebookSyncUpdate>? _syncSubscription;
  DesktopNotesCloudSync? _cloudSync;
  final Map<String, String> _diskContents = {};
  final Set<String> _dirtyIds = {};

  MarkdownDocument? get selectedNote {
    for (final item in notes) {
      if (item.id == selectedId) return item;
    }
    return null;
  }

  MarkdownDocument get note =>
      selectedNote ?? (throw StateError('No hay una nota seleccionada.'));

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    loadFailed = false;
    error = null;
    _emit();
    try {
      final snapshot = await repository.load().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'La lectura de Folio tardó demasiado. Comprueba que la carpeta esté disponible.',
        ),
      );
      _applyInitial(snapshot);
      await refreshRecoveredDrafts();
      _sync = NotebookSyncService(repository);
      _syncSubscription = _sync!.updates.listen(_onSyncUpdate);
      _sync!.start();
      _cloudSync ??= DesktopNotesCloudSync(
        cloudSync: FolioCloudSyncService.instance,
        getRepository: () => repository,
        getCurrentSnapshot: () =>
            NotebookSnapshot(notes: notes, folderPaths: folderPaths),
        isNoteDirty: (id) => _dirtyIds.contains(id),
        onRemoteApplied: _refreshFromDisk,
      );
      _cloudSync!.start();
    } catch (e) {
      loadFailed = true;
      error =
          'No se pudo abrir la carpeta Folio. Comprueba su acceso e inténtalo de nuevo. $e';
    } finally {
      loading = false;
      _emit();
    }
  }

  void _applyInitial(NotebookSnapshot snapshot) {
    storageUnavailable = false;
    notes = snapshot.notes;
    folderPaths = snapshot.folderPaths;
    _diskContents
      ..clear()
      ..addEntries(
        snapshot.notes.map((item) => MapEntry(item.id, item.content)),
      );
    selectedId = notes.isEmpty ? null : notes.first.id;
    contentListenable.value = selectedNote?.content ?? '';
    _setSaveStatus('Guardado');
    if (snapshot.readErrors.isNotEmpty) {
      error = 'Algunos archivos Markdown no se pudieron leer.';
    }
  }

  void _onSyncUpdate(NotebookSyncUpdate update) {
    if (update.error != null) {
      syncing = true;
      storageUnavailable = true;
      error =
          'No se pudo sincronizar Folio. Comprueba los permisos de la carpeta.';
      _emit();
      return;
    }
    final snapshot = update.snapshot;
    if (snapshot == null || _disposed) return;
    syncing = false;
    storageUnavailable = false;
    unawaited(_queueReconcile(snapshot));
  }

  Future<void> _queueReconcile(NotebookSnapshot snapshot) {
    _reconciliations = _reconciliations.then((_) => _reconcile(snapshot));
    return _reconciliations;
  }

  Future<void> _reconcile(NotebookSnapshot snapshot) async {
    final pendingWrites = _writes;
    final mayNeedFreshScan = _dirtyIds.isNotEmpty;
    await pendingWrites;
    final diskSnapshot = mayNeedFreshScan ? await repository.scan() : snapshot;
    final oldSelected = selectedId;
    final byId = {for (final item in diskSnapshot.notes) item.id: item};
    for (final id in _dirtyIds.toList()) {
      final disk = byId[id];
      final previousDisk = _diskContents[id];
      if (disk == null ||
          (previousDisk != null && disk.content != previousDisk)) {
        final local = notes.where((item) => item.id == id);
        if (local.isNotEmpty) {
          await recoveredRepository.save(
            title: local.first.title,
            content: local.first.content,
          );
        }
        _dirtyIds.remove(id);
      }
    }
    _diskContents
      ..clear()
      ..addEntries(
        diskSnapshot.notes.map((item) => MapEntry(item.id, item.content)),
      );
    final previous = {for (final item in notes) item.id: item};
    notes = diskSnapshot.notes.map((disk) {
      final local = previous[disk.id];
      if (local != null && _dirtyIds.contains(disk.id)) return local;
      return disk;
    }).toList();
    folderPaths = diskSnapshot.folderPaths;
    if (oldSelected != null && notes.any((item) => item.id == oldSelected)) {
      selectedId = oldSelected;
    } else {
      selectedId = notes.isEmpty ? null : notes.first.id;
    }
    contentListenable.value = selectedNote?.content ?? '';
    await refreshRecoveredDrafts();
    _emit();
    _cloudSync?.scheduleUpload();
  }

  Future<void> refreshRecoveredDrafts() async {
    try {
      recoveredDrafts = await recoveredRepository.list();
    } catch (_) {
      recoveredDrafts = [];
    }
  }

  void clearError() {
    error = null;
    _emit();
  }

  void reportError(String message) {
    error = message;
    _emit();
  }

  void select(String id) {
    if (!notes.any((item) => item.id == id)) return;
    selectedId = id;
    contentListenable.value = note.content;
    _emit();
  }

  Future<void> create({
    String title = 'Nueva nota',
    String? folder,
    String content = '',
  }) async {
    try {
      final created = await repository.createNote(
        title: title,
        folder: folder,
        content: content,
      );
      notes = [...notes, created]
        ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
      if (folder != null) _addFolderPath(folder);
      selectedId = created.id;
      _diskContents[created.id] = created.content;
      contentListenable.value = created.content;
      _dirtyIds.remove(created.id);
      _emit();
      _cloudSync?.scheduleUpload();
    } catch (e) {
      error = 'No se pudo crear la nota: $e';
      _emit();
    }
  }

  Future<String?> createFolder(String path) async {
    try {
      final actual = await repository.createFolder(path);
      _addFolderPath(actual);
      _emit();
      _cloudSync?.scheduleUpload();
      return actual;
    } catch (e) {
      error = 'No se pudo crear la carpeta: $e';
      _emit();
      return null;
    }
  }

  void _addFolderPath(String path) {
    final parts = path.split('/');
    folderPaths = {
      ...folderPaths,
      for (var i = 0; i < parts.length; i++) parts.take(i + 1).join('/'),
    };
  }

  Future<void> deleteNote(String id) {
    _writes = save().then((_) async {
      try {
        if (_dirtyIds.contains(id)) {
          throw const FileSystemException('La nota tiene cambios sin guardar.');
        }
        await repository.deleteNote(id);
        if (_dirtyIds.contains(id)) {
          final edited = notes.firstWhere((item) => item.id == id);
          await recoveredRepository.save(
            title: edited.title,
            content: edited.content,
          );
          _dirtyIds.remove(id);
        }
        notes = notes.where((item) => item.id != id).toList();
        _diskContents.remove(id);
        if (selectedId == id) {
          selectedId = notes.isEmpty ? null : notes.first.id;
          contentListenable.value = selectedNote?.content ?? '';
        }
        _cloudSync?.scheduleUpload();
      } catch (e) {
        error = 'No se pudo enviar la nota a la papelera: $e';
      }
      _emit();
    });
    return _writes;
  }

  Future<List<TrashedNote>> listTrash() => repository.listTrash();

  Future<MarkdownDocument?> restoreDeletedNote(TrashedNote note) async {
    try {
      final restored = await repository.restoreDeletedNote(note.id);
      _replaceNote(restored.id, restored);
      _diskContents[restored.id] = restored.content;
      if (restored.folder case final folder?) _addFolderPath(folder);
      select(restored.id);
      return restored;
    } catch (e) {
      error = 'No se pudo restaurar la nota: $e';
      _emit();
      return null;
    }
  }

  Future<String?> saveImage(String noteId, Uint8List png) async {
    try {
      return await repository.saveImage(noteId, png);
    } catch (e) {
      error = 'No se pudo pegar la imagen: $e';
      _emit();
      return null;
    }
  }

  Future<Uint8List?> readImage(String noteId, String reference) =>
      repository.readImage(noteId, reference);

  Future<Map<String, String>> deleteFolder(String folder) async {
    try {
      await save();
      if (saveStatus == 'Error al guardar') {
        throw const FileSystemException('Hay cambios sin guardar.');
      }
      final movedNoteIds = repository is FileRepository
          ? await (repository as FileRepository).deleteFolderWithNoteMappings(
              folder,
            )
          : <String, String>{};
      if (repository is! FileRepository) await repository.deleteFolder(folder);
      await _queueReconcile(await repository.scan());
      return movedNoteIds;
    } catch (e) {
      error = 'No se pudo eliminar la carpeta: $e';
      _emit();
      return {};
    }
  }

  void update({String? title, String? content}) {
    final index = notes.indexWhere((item) => item.id == selectedId);
    if (index < 0 || (title == null && content == null)) return;
    final old = notes[index];
    notes = [...notes]
      ..[index] = MarkdownDocument(
        id: old.id,
        title: title ?? old.title,
        content: content ?? old.content,
        folder: old.folder,
      );
    if (content != null) {
      contentListenable.value = content;
      _dirtyIds.add(old.id);
    }
    _changed(notify: title != null);
  }

  Future<MarkdownDocument?> renameNote(String id, String title) =>
      _relocateNote(id, 'renombrar', () => repository.renameNote(id, title));

  Future<MarkdownDocument?> moveToFolder(String id, String? folder) =>
      _relocateNote(id, 'mover', () => repository.moveNote(id, folder));

  Future<MarkdownDocument?> _relocateNote(
    String id,
    String action,
    Future<MarkdownDocument> Function() relocate,
  ) {
    MarkdownDocument? relocatedResult;
    _writes = save().then((_) async {
      if (saveStatus == 'Error al guardar') {
        error = 'No se pudo $action porque hay cambios sin guardar.';
        _emit();
        return;
      }
      if (!notes.any((item) => item.id == id)) return;
      try {
        final relocated = await relocate();
        relocatedResult = relocated;
        final edited = _dirtyIds.remove(id);
        final replacement = edited
            ? relocated.copyWith(
                content: notes.firstWhere((item) => item.id == id).content,
              )
            : relocated;
        _replaceNote(id, replacement);
        _diskContents.remove(id);
        _diskContents[relocated.id] = relocated.content;
        if (relocated.folder case final folder?) _addFolderPath(folder);
        if (edited) {
          _dirtyIds.add(relocated.id);
          _changed(notify: false);
        }
        if (selectedId == id) {
          selectedId = relocated.id;
          contentListenable.value = replacement.content;
        }
        _emit();
        _cloudSync?.scheduleUpload();
      } catch (e) {
        error = 'No se pudo $action la nota: $e';
        _emit();
      }
    });
    return _writes.then((_) => relocatedResult);
  }

  Future<String?> moveFolderTo(String folder, String? destination) async {
    await save();
    if (saveStatus == 'Error al guardar') {
      error = 'No se pudo mover porque hay cambios sin guardar.';
      _emit();
      return null;
    }
    try {
      final moved = await repository.moveFolder(folder, destination);
      await _refreshFromDisk();
      return moved;
    } catch (e) {
      error = 'No se pudo mover la carpeta: $e';
      _emit();
      return null;
    }
  }

  Future<String?> renameFolder(String folder, String title) async {
    await save();
    if (saveStatus == 'Error al guardar') {
      error = 'No se pudo renombrar porque hay cambios sin guardar.';
      _emit();
      return null;
    }
    try {
      final renamed = await repository.renameFolder(folder, title);
      await _refreshFromDisk();
      return renamed;
    } catch (e) {
      error = 'No se pudo renombrar la carpeta: $e';
      _emit();
      return null;
    }
  }

  void _replaceNote(String oldId, MarkdownDocument replacement) {
    notes = [...notes.where((item) => item.id != oldId), replacement]
      ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
  }

  void _changed({bool notify = true}) {
    _revision++;
    _setSaveStatus('Guardando…');
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () => unawaited(save()));
    if (notify) _emit();
  }

  void _setSaveStatus(String value) {
    saveStatus = value;
    saveStatusListenable.value = value;
  }

  Future<void> save() {
    _timer?.cancel();
    if (loading || loadFailed || _dirtyIds.isEmpty) return _writes;
    final ids = _dirtyIds.toList();
    final snapshot = notes.where((item) => ids.contains(item.id)).toList();
    final revision = _revision;
    _writes = _writes.then((_) async {
      try {
        for (final item in snapshot) {
          if (!_dirtyIds.contains(item.id)) continue;
          final saved = await repository.saveNote(item);
          _diskContents[saved.id] = saved.content;
          final current = notes.where((note) => note.id == saved.id);
          if (current.isNotEmpty && current.first.content == saved.content) {
            _dirtyIds.remove(saved.id);
          }
        }
        if (revision == _revision && _dirtyIds.isEmpty) {
          _setSaveStatus('Guardado');
          _cloudSync?.scheduleUpload();
        } else if (_dirtyIds.isNotEmpty) {
          _setSaveStatus('Guardando…');
          _timer?.cancel();
          _timer = Timer(
            const Duration(milliseconds: 30),
            () => unawaited(save()),
          );
        }
      } catch (e) {
        _setSaveStatus('Error al guardar');
        error = 'No se pudieron guardar los cambios: $e';
        _emit();
      }
    });
    return _writes;
  }

  Future<void> _refreshFromDisk() async =>
      _queueReconcile(await repository.scan());

  Future<void> refresh() async {
    try {
      syncing = true;
      _emit();
      await _refreshFromDisk();
      syncing = false;
      storageUnavailable = false;
      error = null;
      _emit();
    } catch (e) {
      syncing = false;
      storageUnavailable = true;
      error = 'No se pudo volver a leer la carpeta Folio: $e';
      _emit();
    }
  }

  Future<void> changeStorageDirectory(
    Directory destination, {
    Future<void> Function()? beforeSwitch,
    Future<void> Function(Map<String, String> noteIds)? copyNotebookData,
  }) async {
    String normalize(String path) => p.normalize(p.absolute(path));
    final oldDirectory = NotesStorage.directory;
    if (oldDirectory != null &&
        normalize(oldDirectory.path) == normalize(destination.path)) {
      return;
    }
    await save();
    if (saveStatus == 'Error al guardar') {
      throw const FileSystemException('Hay cambios sin guardar.');
    }
    final sourceSnapshot = await repository.scan();
    final copied = await FileRepository.copyNotebookInto(
      destination,
      sourceSnapshot,
      sourceRepository: repository is FileRepository
          ? repository as FileRepository
          : null,
      copyNotebookData: copyNotebookData,
    );
    await beforeSwitch?.call();
    if (_disposed) return;
    await _syncSubscription?.cancel();
    await _sync?.dispose();
    repository = FileRepository(directory: destination);
    NotesStorage.directory = destination;
    _applyInitial(copied);
    _sync = NotebookSyncService(repository);
    _syncSubscription = _sync!.updates.listen(_onSyncUpdate);
    _sync!.start();
    _emit();
  }

  Future<void> reselectStorageDirectory(
    Directory destination, {
    Future<void> Function()? beforeSwitch,
  }) async {
    final replacement = FileRepository(directory: destination);
    final snapshot = await replacement.load();
    await beforeSwitch?.call();
    await _syncSubscription?.cancel();
    await _sync?.dispose();
    repository = replacement;
    NotesStorage.directory = destination;
    _applyInitial(snapshot);
    loadFailed = false;
    storageUnavailable = false;
    error = null;
    _sync = NotebookSyncService(repository);
    _syncSubscription = _sync!.updates.listen(_onSyncUpdate);
    _sync!.start();
    await refreshRecoveredDrafts();
    _emit();
  }

  Future<void> importMarkdown() async {
    if (importing) return;
    importing = true;
    _emit();
    try {
      final item = await repository.importMarkdown();
      if (item != null && !_disposed) {
        notes = [...notes, item];
        selectedId = item.id;
        contentListenable.value = item.content;
        _emit();
      }
    } catch (e) {
      error = 'No se pudo abrir el archivo: $e';
    } finally {
      importing = false;
      _emit();
    }
  }

  Future<bool> exportMarkdown() async {
    final item = selectedNote;
    if (item == null) return false;
    try {
      return await repository.exportMarkdown(item);
    } catch (e) {
      error = 'No se pudo exportar la nota: $e';
      _emit();
      return false;
    }
  }

  Future<void> restoreRecovered(RecoveredDraft draft) async {
    final item = await repository.createNote(
      title: draft.title,
      content: draft.content,
    );
    notes = [...notes, item];
    selectedId = item.id;
    contentListenable.value = item.content;
    await recoveredRepository.delete(draft.id);
    await refreshRecoveredDrafts();
    _emit();
  }

  Future<void> deleteRecovered(String id) async {
    await recoveredRepository.delete(id);
    await refreshRecoveredDrafts();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_syncSubscription?.cancel());
    unawaited(_sync?.dispose());
    unawaited(_cloudSync?.dispose());
    contentListenable.dispose();
    saveStatusListenable.dispose();
    super.dispose();
  }
}
