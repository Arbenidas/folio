import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/managed_task.dart';

class TaskRepository {
  TaskRepository(Directory notebookRoot)
    : _file = File(p.join(notebookRoot.path, '.folio-tasks.json'));

  final File _file;

  Future<List<ManagedTask>> load() async {
    if (!await _file.exists()) return const [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['tasks'] is! List) {
      throw const FormatException(
        'El archivo de tareas no tiene un formato compatible.',
      );
    }
    final tasks = (decoded['tasks'] as List).map(ManagedTask.fromJson).toList();
    final ids = tasks.map((task) => task.id).toSet();
    if (ids.length != tasks.length) {
      throw const FormatException(
        'El archivo de tareas contiene identificadores duplicados.',
      );
    }
    return tasks;
  }

  Future<void> save(List<ManagedTask> tasks) async {
    await _file.parent.create(recursive: true);
    final random = Random.secure();
    final temporary = File(
      p.join(
        _file.parent.path,
        '.folio-write-tasks-${pid}-${random.nextInt(1 << 32)}',
      ),
    );
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'tasks': tasks.map((task) => task.toJson()).toList(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> copyTo(
    Directory notebookRoot,
    Map<String, String> noteIds,
  ) async {
    final existing = await TaskRepository(notebookRoot).load();
    final byId = {for (final task in existing) task.id: task};
    for (final task in await load()) {
      final noteId = task.noteId;
      byId.putIfAbsent(
        task.id,
        () => noteId == null || !noteIds.containsKey(noteId)
            ? task
            : task.copyWith(noteId: noteIds[noteId]),
      );
    }
    await TaskRepository(notebookRoot).save(byId.values.toList());
  }
}
