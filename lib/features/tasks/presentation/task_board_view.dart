import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        BoxConstraints,
        ColorScheme,
        Colors,
        InkWell,
        LinearProgressIndicator,
        Material,
        PopupMenuButton,
        PopupMenuItem,
        Theme,
        Tooltip;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/folio_dialogs.dart';
import '../../editor/domain/markdown_document.dart';
import '../../editor/presentation/widgets/editor_motion.dart';
import '../domain/managed_task.dart';
import 'task_controller.dart';

enum _TaskBoardLayout { kanban, eisenhower }

enum _TaskFilter { all, currentNote, active }

class TaskBoardView extends StatefulWidget {
  const TaskBoardView({
    super.key,
    required this.controller,
    required this.notes,
    required this.onOpenNote,
    required this.onCreateNote,
    required this.onBackToNotes,
    this.focusTaskId,
    this.activeNote,
    this.isSidebar = true,
    this.onToggleExpand,
  });

  final TaskController controller;
  final List<MarkdownDocument> notes;
  final ValueChanged<MarkdownDocument> onOpenNote;
  final ValueChanged<ManagedTask> onCreateNote;
  final VoidCallback onBackToNotes;
  final String? focusTaskId;
  final MarkdownDocument? activeNote;
  final bool isSidebar;
  final VoidCallback? onToggleExpand;

  @override
  State<TaskBoardView> createState() => _TaskBoardViewState();
}

class _TaskBoardViewState extends State<TaskBoardView> {
  _TaskBoardLayout _layout = _TaskBoardLayout.kanban;
  _TaskFilter _filter = _TaskFilter.all;
  bool _linkToCurrentNote = false;
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode(debugLabel: 'Nueva tarea');
  GlobalKey? _focusedTaskKey;
  final Set<TaskPhase> _collapsedPhases = {};
  final Set<TaskPriority> _collapsedPriorities = {};

  @override
  void initState() {
    super.initState();
    if (widget.focusTaskId != null) _focusedTaskKey = GlobalKey();
    _revealFocusedTask(widget.focusTaskId);
  }

  @override
  void didUpdateWidget(covariant TaskBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusTaskId != widget.focusTaskId) {
      _focusedTaskKey = widget.focusTaskId == null ? null : GlobalKey();
      _revealFocusedTask(widget.focusTaskId);
    }
    if (oldWidget.isSidebar != widget.isSidebar && widget.focusTaskId != null) {
      _focusedTaskKey = GlobalKey();
    }
    if (widget.activeNote == null && _filter == _TaskFilter.currentNote) {
      _filter = _TaskFilter.all;
    }
  }

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  void _revealFocusedTask(String? id) {
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _focusedTaskKey?.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.25,
          duration: EditorMotion.duration(context, 220),
          curve: EditorMotion.curve,
        );
      }
    });
  }

  static const _phases = {
    TaskPhase.pending: 'Pendiente',
    TaskPhase.inProgress: 'En curso',
    TaskPhase.done: 'Hecha',
  };

  static const _quadrantTitles = {
    TaskPriority.urgentImportant: 'Hacer ya',
    TaskPriority.important: 'Planificar',
    TaskPriority.urgent: 'Delegar',
    TaskPriority.later: 'Más tarde',
    TaskPriority.unassigned: 'Sin priorizar',
  };

  static const _priorities = {
    TaskPriority.urgentImportant: 'Urgente e importante',
    TaskPriority.important: 'Importante · sin urgencia',
    TaskPriority.urgent: 'Urgente · baja importancia',
    TaskPriority.later: 'Baja prioridad',
    TaskPriority.unassigned: 'Sin priorizar',
  };

  List<ManagedTask> get _filteredTasks {
    final all = widget.controller.tasks;
    return switch (_filter) {
      _TaskFilter.all => all,
      _TaskFilter.active =>
        all.where((task) => task.phase != TaskPhase.done).toList(),
      _TaskFilter.currentNote =>
        widget.activeNote == null
            ? all
            : all
                  .where((task) => task.noteId == widget.activeNote!.id)
                  .toList(),
    };
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;
    final activeNote = _linkToCurrentNote ? widget.activeNote : null;
    _quickAddController.clear();
    await widget.controller.create(
      title,
      noteId: activeNote?.id,
      noteTitle: activeNote?.title,
    );
  }

  Future<void> _linkTask(ManagedTask task) async {
    final note = await showFolioPickerDialog<MarkdownDocument>(
      context,
      title: 'Vincular una nota',
      subtitle: 'Elige la nota que da contexto a esta tarea.',
      icon: CupertinoIcons.link,
      emptyMessage: 'No hay notas disponibles para vincular.',
      items: [
        for (final item in widget.notes)
          FolioPickerItem(
            value: item,
            title: item.title,
            subtitle: item.folder?.replaceAll('/', '  ›  '),
            icon: CupertinoIcons.doc_text,
          ),
      ],
    );
    if (note != null) {
      await widget.controller.linkNote(
        task,
        noteId: note.id,
        noteTitle: note.title,
      );
    }
  }

  Future<void> _openLinkedNote(ManagedTask task) async {
    final noteId = task.noteId;
    final matches = widget.notes.where((note) => note.id == noteId);
    if (matches.isNotEmpty) {
      widget.onOpenNote(matches.first);
      return;
    }
    widget.onCreateNote(task);
  }

  Future<void> _renameTask(ManagedTask task) async {
    final title = await showFolioPromptDialog(
      context,
      title: 'Renombrar tarea',
      initial: task.title,
      hint: 'Nombre de la tarea',
      confirmLabel: 'Guardar',
      maxLength: 120,
    );
    if (title != null) await widget.controller.rename(task, title);
  }

  Future<void> _deleteTask(ManagedTask task) async {
    final confirmed = await showFolioConfirmDialog(
      context,
      title: 'Eliminar tarea',
      message:
          'Se eliminará «${task.title}». Esta acción no se puede deshacer.',
      actionLabel: 'Eliminar',
    );
    if (confirmed) await widget.controller.delete(task);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final style = FolioStyle.of(context);
        if (widget.controller.loading) {
          return ColoredBox(
            color: colors.surfaceContainerLow,
            child: const Center(child: CupertinoActivityIndicator()),
          );
        }
        if (widget.controller.error != null &&
            widget.controller.tasks.isEmpty) {
          return ColoredBox(
            color: colors.surfaceContainerLow,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.controller.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    CupertinoButton.filled(
                      onPressed: widget.controller.retry,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final allTasks = widget.controller.tasks;
        final doneCount = allTasks
            .where((t) => t.phase == TaskPhase.done)
            .length;
        final noteTaskCount = widget.activeNote == null
            ? 0
            : allTasks.where((t) => t.noteId == widget.activeNote!.id).length;

        return ColoredBox(
          color: widget.isSidebar ? colors.surfaceContainerLow : colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(colors, style, doneCount, allTasks.length),
              _controls(colors, style, noteTaskCount),
              _quickAddComposer(colors),
              if (widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    widget.controller.error!,
                    style: TextStyle(color: colors.error, fontSize: 11.5),
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: EditorMotion.duration(context, 180),
                  switchInCurve: EditorMotion.curve,
                  switchOutCurve: EditorMotion.reverseCurve,
                  child: KeyedSubtree(
                    key: ValueKey((_layout, widget.isSidebar)),
                    child: _layout == _TaskBoardLayout.kanban
                        ? _kanban(colors)
                        : _matrix(colors),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _header(
    ColorScheme colors,
    FolioStyle style,
    int doneCount,
    int totalCount,
  ) {
    final progress = totalCount > 0
        ? (doneCount / totalCount).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      height: 46,
      padding: EdgeInsets.fromLTRB(widget.isSidebar ? 14 : 20, 4, 10, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: style.isGraphic ? style.ink : colors.outlineVariant,
            width: style.isGraphic ? style.lineWidth : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              LucideIcons.listTodo,
              size: 13.5,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'TAREAS',
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: style.isRetro ? 'Menlo' : null,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: totalCount > 0 && doneCount == totalCount
                  ? colors.secondaryContainer
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$doneCount/$totalCount',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (totalCount > 0 && !widget.isSidebar) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 44,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: colors.outlineVariant,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (widget.onToggleExpand != null)
            Tooltip(
              message: widget.isSidebar
                  ? 'Ampliar tablero completo'
                  : 'Acoplar como barra lateral',
              child: AppIconButton(
                semanticLabel: widget.isSidebar
                    ? 'Ampliar tablero'
                    : 'Acoplar como barra lateral',
                icon: widget.isSidebar
                    ? CupertinoIcons.arrow_up_left_arrow_down_right
                    : CupertinoIcons.sidebar_right,
                size: 15,
                padding: const EdgeInsets.all(5),
                onPressed: widget.onToggleExpand,
              ),
            ),
          Tooltip(
            message: widget.isSidebar ? 'Ocultar tareas' : 'Volver a notas',
            child: AppIconButton(
              semanticLabel: 'Cerrar tareas',
              icon: CupertinoIcons.xmark,
              size: 15,
              padding: const EdgeInsets.all(5),
              onPressed: widget.onBackToNotes,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(
    ColorScheme colors,
    FolioStyle style,
    int noteTaskCount,
  ) {
    final switcher = CupertinoSlidingSegmentedControl<_TaskBoardLayout>(
      groupValue: _layout,
      backgroundColor: colors.surfaceContainerHigh,
      thumbColor: colors.surfaceContainerLowest,
      children: {
        _TaskBoardLayout.kanban: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.columns3,
                size: 13.5,
                color: _layout == _TaskBoardLayout.kanban
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Kanban',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _layout == _TaskBoardLayout.kanban
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _layout == _TaskBoardLayout.kanban
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _TaskBoardLayout.eisenhower: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.layoutGrid,
                size: 13.5,
                color: _layout == _TaskBoardLayout.eisenhower
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Eisenhower',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _layout == _TaskBoardLayout.eisenhower
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _layout == _TaskBoardLayout.eisenhower
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      },
      onValueChanged: (value) {
        if (value != null) {
          setState(() {
            _layout = value;
            if (widget.focusTaskId != null) _focusedTaskKey = GlobalKey();
          });
        }
      },
    );

    final filtersRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('Todas', _TaskFilter.all, colors),
          const SizedBox(width: 6),
          _filterChip('Activas', _TaskFilter.active, colors),
          if (widget.activeNote != null) ...[
            const SizedBox(width: 6),
            _filterChip(
              noteTaskCount > 0 ? 'Esta nota ($noteTaskCount)' : 'Esta nota',
              _TaskFilter.currentNote,
              colors,
            ),
          ],
        ],
      ),
    );

    if (!widget.isSidebar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 280, child: switcher),
            filtersRow,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switcher,
          const SizedBox(height: 8),
          filtersRow,
        ],
      ),
    );
  }

  Widget _filterChip(String label, _TaskFilter value, ColorScheme colors) {
    final selected = _filter == value;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 150),
        curve: EditorMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.45)
                : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _quickAddComposer(ColorScheme colors) => Padding(
    padding: EdgeInsets.fromLTRB(
      widget.isSidebar ? 12 : 20,
      2,
      widget.isSidebar ? 12 : 20,
      12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _quickAddController,
                focusNode: _quickAddFocus,
                placeholder: 'Nueva tarea… (Enter para añadir)',
                maxLength: 120,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Icon(
                    LucideIcons.circlePlus,
                    size: 15,
                    color: colors.primary,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9.5,
                ),
                style: TextStyle(fontSize: 13, color: colors.onSurface),
                placeholderStyle: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: colors.outlineVariant),
                ),
                onSubmitted: (_) => _submitQuickAdd(),
              ),
            ),
            const SizedBox(width: 7),
            Tooltip(
              message: 'Crear tarea',
              child: CupertinoButton(
                padding: const EdgeInsets.all(9),
                minimumSize: Size.zero,
                color: colors.primary,
                borderRadius: BorderRadius.circular(11),
                onPressed: _submitQuickAdd,
                child: Icon(
                  LucideIcons.plus,
                  size: 16,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ],
        ),
        if (widget.activeNote != null) ...[
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _linkToCurrentNote = !_linkToCurrentNote),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: EditorMotion.duration(context, 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: _linkToCurrentNote
                        ? colors.primary.withValues(alpha: 0.14)
                        : colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _linkToCurrentNote
                          ? colors.primary.withValues(alpha: 0.45)
                          : colors.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _linkToCurrentNote
                            ? LucideIcons.circleCheck
                            : LucideIcons.fileText,
                        size: 12.5,
                        color: _linkToCurrentNote
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Vincular a «${widget.activeNote!.title}»',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _linkToCurrentNote
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _linkToCurrentNote
                                ? colors.primary
                                : colors.onSurfaceVariant,
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
      ],
    ),
  );

  Widget _kanban(ColorScheme colors) {
    final phases = TaskPhase.values;
    final tasks = _filteredTasks;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = !widget.isSidebar && constraints.maxWidth >= 660;
        if (horizontal) {
          final laneWidth = (constraints.maxWidth - 64) / 3;
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              for (final phase in phases)
                _phaseLane(
                  phase,
                  tasks.where((t) => t.phase == phase).toList(),
                  colors,
                  width: laneWidth,
                ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
          children: [
            for (final phase in phases)
              _phaseLane(
                phase,
                tasks.where((t) => t.phase == phase).toList(),
                colors,
              ),
          ],
        );
      },
    );
  }

  IconData _phaseIcon(TaskPhase phase) => switch (phase) {
    TaskPhase.pending => LucideIcons.circleDashed,
    TaskPhase.inProgress => LucideIcons.play,
    TaskPhase.done => LucideIcons.circleCheck,
  };

  IconData _priorityIcon(TaskPriority priority) => switch (priority) {
    TaskPriority.urgentImportant => LucideIcons.flame,
    TaskPriority.important => LucideIcons.calendarClock,
    TaskPriority.urgent => LucideIcons.zap,
    TaskPriority.later => LucideIcons.clock,
    TaskPriority.unassigned => LucideIcons.inbox,
  };

  Widget _phaseLane(
    TaskPhase phase,
    List<ManagedTask> tasks,
    ColorScheme colors, {
    double? width,
  }) {
    final collapsed = width == null && _collapsedPhases.contains(phase);
    final phaseColor = _phaseColor(phase, colors);
    return DragTarget<ManagedTask>(
      onWillAcceptWithDetails: (details) => details.data.phase != phase,
      onAcceptWithDetails: (details) {
        widget.controller.updatePhase(details.data, phase);
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: EditorMotion.duration(context, 170),
          curve: EditorMotion.curve,
          width: width,
          margin: EdgeInsets.only(
            right: width != null ? 12 : 0,
            bottom: 10,
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: hovering
                ? phaseColor.withValues(alpha: 0.10)
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering
                  ? phaseColor
                  : colors.outlineVariant,
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: width == null
                    ? () => setState(() {
                        if (!_collapsedPhases.add(phase)) {
                          _collapsedPhases.remove(phase);
                        }
                      })
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 1, 2, 8),
                  child: Row(
                    children: [
                      if (width == null) ...[
                        AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: EditorMotion.duration(context, 160),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: phaseColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          _phaseIcon(phase),
                          size: 13,
                          color: phaseColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _phases[phase]!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      _count(tasks.length, colors, accent: phaseColor),
                    ],
                  ),
                ),
              ),
              if (width == null)
                ClipRect(
                  child: AnimatedSize(
                    duration: EditorMotion.duration(context, 200),
                    curve: EditorMotion.emphasizedCurve,
                    alignment: Alignment.topCenter,
                    child: collapsed
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (tasks.isEmpty)
                                _emptyDropHint(
                                  hovering
                                      ? 'Suelta para mover aquí'
                                      : 'Arrastra una tarea aquí',
                                  colors,
                                  icon: _phaseIcon(phase),
                                  accent: phaseColor,
                                  compact: true,
                                ),
                              for (final task in tasks) _card(task, colors),
                            ],
                          ),
                  ),
                )
              else
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: _emptyDropHint(
                            hovering
                                ? 'Suelta para mover aquí'
                                : 'Arrastra una tarea aquí',
                            colors,
                            icon: _phaseIcon(phase),
                            accent: phaseColor,
                            compact: false,
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final task in tasks) _card(task, colors),
                          ],
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _matrix(ColorScheme colors) {
    final priorities = TaskPriority.values
        .where((priority) => priority != TaskPriority.unassigned)
        .toList();
    final filtered = _filteredTasks
        .where((task) => task.phase != TaskPhase.done)
        .toList();
    final unassigned = filtered
        .where((task) => task.priority == TaskPriority.unassigned)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridMode = !widget.isSidebar && constraints.maxWidth >= 660;
        if (gridMode) {
          return GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.65,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              for (final priority in priorities)
                _quadrantSection(
                  priority,
                  filtered.where((t) => t.priority == priority).toList(),
                  colors,
                  expandScroll: true,
                ),
              if (unassigned.isNotEmpty)
                _quadrantSection(
                  TaskPriority.unassigned,
                  unassigned,
                  colors,
                  expandScroll: true,
                ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
          children: [
            if (unassigned.isNotEmpty)
              _quadrantSection(
                TaskPriority.unassigned,
                unassigned,
                colors,
                expandScroll: false,
              ),
            for (final priority in priorities)
              _quadrantSection(
                priority,
                filtered.where((t) => t.priority == priority).toList(),
                colors,
                expandScroll: false,
              ),
          ],
        );
      },
    );
  }

  Widget _quadrantSection(
    TaskPriority priority,
    List<ManagedTask> tasks,
    ColorScheme colors, {
    required bool expandScroll,
  }) {
    final priorityColor = _priorityColor(priority, colors);
    final collapsed = !expandScroll && _collapsedPriorities.contains(priority);
    return DragTarget<ManagedTask>(
      onWillAcceptWithDetails: (details) => details.data.priority != priority,
      onAcceptWithDetails: (details) {
        widget.controller.updatePriority(details.data, priority);
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: EditorMotion.duration(context, 170),
          curve: EditorMotion.curve,
          margin: expandScroll
              ? EdgeInsets.zero
              : const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: hovering
                ? priorityColor.withValues(alpha: 0.12)
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering
                  ? priorityColor
                  : priorityColor.withValues(alpha: 0.35),
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: expandScroll
                    ? null
                    : () => setState(() {
                        if (!_collapsedPriorities.add(priority)) {
                          _collapsedPriorities.remove(priority);
                        }
                      }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 1, 2, 8),
                  child: Row(
                    children: [
                      if (!expandScroll) ...[
                        AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: EditorMotion.duration(context, 160),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _priorityIcon(priority),
                          size: 13.5,
                          color: priorityColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _quadrantTitles[priority]!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            if (priority != TaskPriority.unassigned)
                              Text(
                                _priorities[priority]!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _count(tasks.length, colors, accent: priorityColor),
                    ],
                  ),
                ),
              ),
              if (expandScroll)
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: _emptyDropHint(
                            hovering
                                ? 'Suelta para priorizar aquí'
                                : 'Arrastra una tarea aquí',
                            colors,
                            icon: _priorityIcon(priority),
                            accent: priorityColor,
                            compact: false,
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final task in tasks) _card(task, colors),
                          ],
                        ),
                )
              else
                ClipRect(
                  child: AnimatedSize(
                    duration: EditorMotion.duration(context, 200),
                    curve: EditorMotion.emphasizedCurve,
                    alignment: Alignment.topCenter,
                    child: collapsed
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (tasks.isEmpty)
                                _emptyDropHint(
                                  hovering
                                      ? 'Suelta para priorizar aquí'
                                      : 'Arrastra una tarea aquí',
                                  colors,
                                  icon: _priorityIcon(priority),
                                  accent: priorityColor,
                                  compact: true,
                                ),
                              for (final task in tasks) _card(task, colors),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyDropHint(
    String text,
    ColorScheme colors, {
    required IconData icon,
    required Color accent,
    required bool compact,
  }) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: compact ? 12 : 20,
    ),
    decoration: BoxDecoration(
      color: colors.surface.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: colors.outlineVariant.withValues(alpha: 0.7),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: compact ? 16 : 20,
          color: accent.withValues(alpha: 0.65),
        ),
        const SizedBox(height: 5),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _card(ManagedTask task, ColorScheme colors) {
    final note = widget.notes.where((item) => item.id == task.noteId);
    final linkedNote = note.isNotEmpty ? note.first : null;
    final priorityColor = _priorityColor(task.priority, colors);
    return Draggable<ManagedTask>(
      key: task.id == widget.focusTaskId && _focusedTaskKey != null
          ? _focusedTaskKey
          : ValueKey(task.id),
      data: task,
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 280,
          child: _TaskCard(
            task: task,
            linkedNote: linkedNote,
            priorityColor: priorityColor,
            priorityLabel: _quadrantTitles[task.priority]!,
            layout: _layout,
            hasNotes: widget.notes.isNotEmpty,
            isFocused: widget.focusTaskId == task.id,
            onToggleDone: () {},
            onAdvancePhase: () {},
            onSelectPhase: (_) {},
            onSelectPriority: (_) {},
            onOpenLinkedNote: () {},
            onLinkNote: () {},
            onCreateNote: () {},
            onRename: () {},
            onUnlink: () {},
            onDelete: () {},
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _TaskCard(
          task: task,
          linkedNote: linkedNote,
          priorityColor: priorityColor,
          priorityLabel: _quadrantTitles[task.priority]!,
          layout: _layout,
          hasNotes: widget.notes.isNotEmpty,
          isFocused: false,
          onToggleDone: () {},
          onAdvancePhase: () {},
          onSelectPhase: (_) {},
          onSelectPriority: (_) {},
          onOpenLinkedNote: () {},
          onLinkNote: () {},
          onCreateNote: () {},
          onRename: () {},
          onUnlink: () {},
          onDelete: () {},
        ),
      ),
      child: _TaskCard(
        task: task,
        linkedNote: linkedNote,
        priorityColor: priorityColor,
        priorityLabel: _quadrantTitles[task.priority]!,
        layout: _layout,
        hasNotes: widget.notes.isNotEmpty,
        isFocused: widget.focusTaskId == task.id,
        onToggleDone: () => task.phase == TaskPhase.done
            ? widget.controller.reopen(task)
            : widget.controller.updatePhase(task, TaskPhase.done),
        onAdvancePhase: () {
          final next = switch (task.phase) {
            TaskPhase.pending => TaskPhase.inProgress,
            TaskPhase.inProgress => TaskPhase.done,
            TaskPhase.done => TaskPhase.pending,
          };
          widget.controller.updatePhase(task, next);
        },
        onSelectPhase: (phase) => widget.controller.updatePhase(task, phase),
        onSelectPriority: (priority) =>
            widget.controller.updatePriority(task, priority),
        onOpenLinkedNote: () => _openLinkedNote(task),
        onLinkNote: () => _linkTask(task),
        onCreateNote: () => widget.onCreateNote(task),
        onRename: () => _renameTask(task),
        onUnlink: () => widget.controller.unlinkNote(task),
        onDelete: () => _deleteTask(task),
      ),
    );
  }

  Widget _count(int value, ColorScheme colors, {Color? accent}) => DecoratedBox(
    decoration: BoxDecoration(
      color: accent != null
          ? accent.withValues(alpha: 0.14)
          : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: accent ?? colors.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );

  Color _phaseColor(TaskPhase phase, ColorScheme colors) => switch (phase) {
    TaskPhase.pending => colors.onSurfaceVariant,
    TaskPhase.inProgress => colors.primary,
    TaskPhase.done => colors.secondary,
  };

  Color _priorityColor(TaskPriority priority, ColorScheme colors) =>
      switch (priority) {
        TaskPriority.urgentImportant => colors.error,
        TaskPriority.important => colors.primary,
        TaskPriority.urgent => colors.tertiary,
        TaskPriority.later => colors.secondary,
        TaskPriority.unassigned => colors.outline,
      };
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.task,
    required this.linkedNote,
    required this.priorityColor,
    required this.priorityLabel,
    required this.layout,
    required this.hasNotes,
    required this.isFocused,
    required this.onToggleDone,
    required this.onAdvancePhase,
    required this.onSelectPhase,
    required this.onSelectPriority,
    required this.onOpenLinkedNote,
    required this.onLinkNote,
    required this.onCreateNote,
    required this.onRename,
    required this.onUnlink,
    required this.onDelete,
  });

  final ManagedTask task;
  final MarkdownDocument? linkedNote;
  final Color priorityColor;
  final String priorityLabel;
  final _TaskBoardLayout layout;
  final bool hasNotes;
  final bool isFocused;
  final VoidCallback onToggleDone;
  final VoidCallback onAdvancePhase;
  final ValueChanged<TaskPhase> onSelectPhase;
  final ValueChanged<TaskPriority> onSelectPriority;
  final VoidCallback onOpenLinkedNote;
  final VoidCallback onLinkNote;
  final VoidCallback onCreateNote;
  final VoidCallback onRename;
  final VoidCallback onUnlink;
  final VoidCallback onDelete;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hovered = false;

  static const _phases = {
    TaskPhase.pending: 'Pendiente',
    TaskPhase.inProgress: 'En curso',
    TaskPhase.done: 'Hecha',
  };

  static const _priorities = {
    TaskPriority.urgentImportant: 'Hacer ya · Urgente e importante',
    TaskPriority.important: 'Planificar · Importante',
    TaskPriority.urgent: 'Delegar · Urgente',
    TaskPriority.later: 'Más tarde · Baja prioridad',
    TaskPriority.unassigned: 'Sin priorizar',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final task = widget.task;
    final done = task.phase == TaskPhase.done;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 150),
        curve: EditorMotion.curve,
        margin: const EdgeInsets.only(bottom: 7),
        decoration: style.isGraphic
            ? style.panel(
                colors.surfaceContainerLowest,
                lift: _hovered ? 3 : 1,
              )
            : BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.isFocused
                      ? colors.primary
                      : _hovered
                      ? colors.outline
                      : colors.outlineVariant,
                  width: widget.isFocused ? 1.5 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3.5,
                color: done
                    ? colors.outlineVariant
                    : widget.priorityColor.withValues(alpha: 0.8),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: task.noteId == null
                        ? null
                        : widget.onOpenLinkedNote,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CupertinoButton(
                                padding: const EdgeInsets.only(top: 1),
                                minimumSize: const Size(24, 24),
                                onPressed: widget.onToggleDone,
                                child: AnimatedSwitcher(
                                  duration: EditorMotion.duration(context, 150),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                        scale: anim,
                                        child: child,
                                      ),
                                  child: Icon(
                                    done
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle,
                                    key: ValueKey(done),
                                    size: 18,
                                    color: done
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    task.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.32,
                                      fontWeight: FontWeight.w600,
                                      color: done
                                          ? colors.onSurfaceVariant
                                          : colors.onSurface,
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedOpacity(
                                opacity: _hovered ? 1 : 0.38,
                                duration: EditorMotion.duration(context, 120),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (task.phase == TaskPhase.pending)
                                      Tooltip(
                                        message: 'Iniciar (En curso)',
                                        child: CupertinoButton(
                                          padding: const EdgeInsets.all(3),
                                          minimumSize: const Size(24, 24),
                                          onPressed: widget.onAdvancePhase,
                                          child: Icon(
                                            CupertinoIcons.play_fill,
                                            size: 12,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                    PopupMenuButton<Object>(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 160,
                                      ),
                                      iconSize: 15,
                                      tooltip:
                                          widget.layout ==
                                              _TaskBoardLayout.kanban
                                          ? 'Cambiar fase'
                                          : 'Cambiar prioridad',
                                      icon: Icon(
                                        CupertinoIcons.arrow_right_arrow_left,
                                        size: 14,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      onSelected: (value) {
                                        if (value is TaskPhase) {
                                          widget.onSelectPhase(value);
                                        } else if (value is TaskPriority) {
                                          widget.onSelectPriority(value);
                                        }
                                      },
                                      itemBuilder: (context) =>
                                          widget.layout ==
                                              _TaskBoardLayout.kanban
                                          ? [
                                              for (final phase
                                                  in TaskPhase.values)
                                                PopupMenuItem(
                                                  value: phase,
                                                  child: Text(_phases[phase]!),
                                                ),
                                            ]
                                          : [
                                              for (final priority
                                                  in TaskPriority.values)
                                                PopupMenuItem(
                                                  value: priority,
                                                  child: Text(
                                                    _priorities[priority]!,
                                                  ),
                                                ),
                                            ],
                                    ),
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      iconSize: 15,
                                      tooltip: 'Opciones de tarea',
                                      icon: Icon(
                                        CupertinoIcons.ellipsis,
                                        size: 14,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      onSelected: (action) {
                                        if (action == 'rename') {
                                          widget.onRename();
                                        }
                                        if (action == 'delete') {
                                          widget.onDelete();
                                        }
                                        if (action == 'unlink') {
                                          widget.onUnlink();
                                        }
                                        if (action == 'link') {
                                          widget.onLinkNote();
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Renombrar'),
                                        ),
                                        if (task.noteId == null &&
                                            widget.hasNotes)
                                          const PopupMenuItem(
                                            value: 'link',
                                            child: Text('Vincular nota…'),
                                          ),
                                        if (task.noteId != null)
                                          const PopupMenuItem(
                                            value: 'unlink',
                                            child: Text('Desvincular nota'),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            'Eliminar tarea',
                                            style: TextStyle(
                                              color: colors.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (task.priority != TaskPriority.unassigned)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.priorityColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.priorityLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: widget.priorityColor,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'Sin priorizar',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (widget.linkedNote case final note?)
                                Tooltip(
                                  message: 'Abrir nota ${note.title}',
                                  child: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    color: colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(6),
                                    onPressed: widget.onOpenLinkedNote,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 135,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            CupertinoIcons.doc_text,
                                            size: 11.5,
                                            color: colors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              note.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: colors.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else if (task.noteId != null)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  onPressed: widget.onCreateNote,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.doc_text,
                                        size: 11.5,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Crear nota',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_hovered && widget.hasNotes)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  onPressed: widget.onLinkNote,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.link,
                                        size: 11.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Vincular',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
