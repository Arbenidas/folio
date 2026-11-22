import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../domain/managed_task.dart';

class TaskController extends ChangeNotifier {
  TaskController(this._repository);

  TaskRepository _repository;
  List<ManagedTask> tasks = const [];
  bool loading = true;
  String? error;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  Future<void> load() async {
    loading = true;
    error = null;
    _emit();
    try {
      tasks = await _repository.load();
    } catch (exception) {
      error =
          'No se pudieron abrir las tareas. Conservamos el archivo para recuperarlo. $exception';
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<void> retry() => tasks.isNotEmpty ? _saveCurrent() : load();

  Future<void> flush() async {
    await _writes;
    if (error != null && tasks.isEmpty) {
      throw const FileSystemException(
        'No se pudieron guardar las tareas antes de copiar el cuaderno.',
      );
    }
    await _repository.save(List<ManagedTask>.unmodifiable(tasks));
  }

  Future<ManagedTask?> create(
    String title, {
    TaskPhase phase = TaskPhase.pending,
    TaskPriority priority = TaskPriority.unassigned,
    String? noteId,
    String? noteTitle,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
    final task = ManagedTask(
      id: id,
      title: trimmed,
      phase: phase,
      priority: priority,
      createdAt: DateTime.now(),
      noteId: noteId,
      noteTitle: noteTitle,
    );
    return await _update([...tasks, task]) ? task : null;
  }

  Future<void> updatePhase(ManagedTask task, TaskPhase phase) => _update([
    for (final current in tasks)
      if (current.id == task.id)
        current.copyWith(
          phase: phase,
          previousPhase: phase == TaskPhase.done
              ? current.phase
              : current.previousPhase,
        )
      else
        current,
  ]);

  Future<void> reopen(ManagedTask task) => updatePhase(
    task,
    task.previousPhase == TaskPhase.inProgress
        ? TaskPhase.inProgress
        : TaskPhase.pending,
  );

  Future<void> updatePriority(ManagedTask task, TaskPriority priority) =>
      _update([
        for (final current in tasks)
          current.id == task.id
              ? current.copyWith(priority: priority)
              : current,
      ]);

  Future<void> rename(ManagedTask task, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return Future.value();
    return _update([
      for (final current in tasks)
        current.id == task.id ? current.copyWith(title: trimmed) : current,
    ]);
  }

  Future<void> delete(ManagedTask task) => _update([
    for (final current in tasks)
      if (current.id != task.id) current,
  ]);

  Future<void> linkNote(
    ManagedTask task, {
    required String noteId,
    required String noteTitle,
  }) => _update([
    for (final current in tasks)
      current.id == task.id
          ? current.copyWith(noteId: noteId, noteTitle: noteTitle)
          : current,
  ]);

  Future<void> relocateNotes(
    Map<String, String> noteIds, {
    Map<String, String> titles = const {},
  }) => _update([
    for (final current in tasks)
      if (current.noteId case final oldId? when noteIds.containsKey(oldId))
        current.copyWith(
          noteId: noteIds[oldId],
          noteTitle: titles[oldId] ?? current.noteTitle,
        )
      else
        current,
  ]);

  Future<void> unlinkNote(ManagedTask task) => _update([
    for (final current in tasks)
      current.id == task.id ? current.copyWith(clearNote: true) : current,
  ]);

  Future<void> changeNotebook(Directory notebookRoot) async {
    await _writes;
    _repository = TaskRepository(notebookRoot);
    await load();
  }

  Future<bool> _update(List<ManagedTask> next) async {
    final snapshot = List<ManagedTask>.unmodifiable(next);
    tasks = snapshot;
    error = null;
    _emit();
    final write = _writes.then((_) => _repository.save(snapshot));
    _writes = write.then(
      (_) {
        if (identical(tasks, snapshot)) error = null;
      },
      onError: (Object exception) {
        if (identical(tasks, snapshot)) {
          error =
              'No se pudieron guardar las tareas. Vuelve a intentarlo. $exception';
          _emit();
        }
      },
    );
    try {
      await write;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveCurrent() async {
    final snapshot = List<ManagedTask>.unmodifiable(tasks);
    try {
      await _writes;
      await _repository.save(snapshot);
      error = null;
    } catch (exception) {
      error =
          'No se pudieron guardar las tareas. Vuelve a intentarlo. $exception';
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
