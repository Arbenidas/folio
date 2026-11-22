enum TaskPhase { pending, inProgress, done }

enum TaskPriority { urgentImportant, important, urgent, later, unassigned }

class ManagedTask {
  const ManagedTask({
    required this.id,
    required this.title,
    required this.phase,
    required this.priority,
    required this.createdAt,
    this.previousPhase,
    this.noteId,
    this.noteTitle,
  });

  final String id;
  final String title;
  final TaskPhase phase;
  final TaskPriority priority;
  final DateTime createdAt;
  final TaskPhase? previousPhase;
  final String? noteId;
  final String? noteTitle;

  ManagedTask copyWith({
    String? title,
    TaskPhase? phase,
    TaskPhase? previousPhase,
    TaskPriority? priority,
    String? noteId,
    String? noteTitle,
    bool clearNote = false,
  }) => ManagedTask(
    id: id,
    title: title ?? this.title,
    phase: phase ?? this.phase,
    priority: priority ?? this.priority,
    createdAt: createdAt,
    previousPhase: previousPhase ?? this.previousPhase,
    noteId: clearNote ? null : noteId ?? this.noteId,
    noteTitle: clearNote ? null : noteTitle ?? this.noteTitle,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'phase': phase.name,
    'priority': priority.name,
    'createdAt': createdAt.toIso8601String(),
    'previousPhase': previousPhase?.name,
    'noteId': noteId,
    'noteTitle': noteTitle,
  };

  static ManagedTask fromJson(Object? value) {
    if (value case {
      'id': final String id,
      'title': final String title,
      'phase': final String phase,
      'priority': final String priority,
      'createdAt': final String createdAt,
    }) {
      return ManagedTask(
        id: id,
        title: title,
        phase: TaskPhase.values.byName(phase),
        priority: TaskPriority.values.byName(priority),
        createdAt: DateTime.parse(createdAt),
        previousPhase: switch (value['previousPhase']) {
          final String value => TaskPhase.values.byName(value),
          _ => null,
        },
        noteId: value['noteId'] as String?,
        noteTitle: value['noteTitle'] as String?,
      );
    }
    throw const FormatException('El registro de una tarea no es válido.');
  }
}
