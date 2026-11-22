import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/managed_task.dart';

/// Bridges Folio's Flutter tasks, finance tracker, daily note, active theme,
/// and native macOS notifications with the WidgetKit extension & Menu Bar app.
class DesktopWidgetBridge {
  DesktopWidgetBridge({
    required this.onApplyToggles,
    required this.onOpenTasks,
    this.onOpenFinance,
    this.onOpenDaily,
  }) {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static const _channel = MethodChannel('folio/widget');

  final Future<void> Function(List<String> taskIds) onApplyToggles;
  final void Function(String? taskId) onOpenTasks;
  final void Function(bool openNew)? onOpenFinance;
  final VoidCallback? onOpenDaily;
  String? _lastSyncedPayload;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'applyToggles':
        final raw = call.arguments;
        if (raw is List) {
          final ids = raw.whereType<String>().toList();
          if (ids.isNotEmpty) await onApplyToggles(ids);
        }
      case 'openTasks':
        onOpenTasks(call.arguments as String?);
      case 'openFinance':
        onOpenFinance?.call(call.arguments == true);
      case 'openDaily':
        onOpenDaily?.call();
    }
    return null;
  }

  Future<void> consumePendingToggles() async {
    if (!Platform.isMacOS) return;
    try {
      final raw = await _channel.invokeListMethod<String>(
        'consumePendingToggles',
      );
      if (raw != null && raw.isNotEmpty) {
        await onApplyToggles(raw);
      }
    } catch (_) {}
  }

  Future<void> notify({required String title, required String body}) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('notify', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  Future<void> sync({
    required List<ManagedTask> tasks,
    required ColorScheme colors,
    Map<String, dynamic>? finance,
    Map<String, dynamic>? daily,
  }) async {
    if (!Platform.isMacOS) return;
    final doneCount = tasks.where((t) => t.phase == TaskPhase.done).length;
    final active = tasks.where((t) => t.phase != TaskPhase.done).toList()
      ..sort((a, b) {
        final phaseOrder = _phaseRank(a.phase).compareTo(_phaseRank(b.phase));
        if (phaseOrder != 0) return phaseOrder;
        final prioOrder = _priorityRank(
          a.priority,
        ).compareTo(_priorityRank(b.priority));
        if (prioOrder != 0) return prioOrder;
        return a.createdAt.compareTo(b.createdAt);
      });

    final payload = jsonEncode({
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'theme': {
        'surface': _hex(colors.surface),
        'card': _hex(colors.surfaceContainerLowest),
        'ink': _hex(colors.onSurface),
        'muted': _hex(colors.onSurfaceVariant),
        'primary': _hex(colors.primary),
        'onPrimary': _hex(colors.onPrimary),
        'error': _hex(colors.error),
        'tertiary': _hex(colors.tertiary),
        'outline': _hex(colors.outlineVariant),
        'isDark': colors.brightness == Brightness.dark,
      },
      'doneCount': doneCount,
      'totalCount': tasks.length,
      'inProgressCount': active
          .where((t) => t.phase == TaskPhase.inProgress)
          .length,
      'tasks': [
        for (final task in active.take(12))
          {
            'id': task.id,
            'title': task.title,
            'phase': task.phase.name,
            'priority': task.priority.name,
            if (task.noteTitle != null) 'noteTitle': task.noteTitle,
          },
      ],
      'finance': ?finance,
      'daily': ?daily,
    });

    // Skip redundant writes if snapshot (ignoring timestamp) didn't change.
    final signature = payload.replaceFirst(RegExp(r'"updatedAt":\d+,'), '');
    if (signature == _lastSyncedPayload) return;
    _lastSyncedPayload = signature;

    try {
      await _channel.invokeMethod<void>('sync', payload);
    } catch (_) {}
  }

  static int _phaseRank(TaskPhase phase) => switch (phase) {
    TaskPhase.inProgress => 0,
    TaskPhase.pending => 1,
    TaskPhase.done => 2,
  };

  static int _priorityRank(TaskPriority priority) => switch (priority) {
    TaskPriority.urgentImportant => 0,
    TaskPriority.important => 1,
    TaskPriority.urgent => 2,
    TaskPriority.later => 3,
    TaskPriority.unassigned => 4,
  };

  static String _hex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${(r + g + b).toUpperCase()}';
  }

  void dispose() {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(null);
    }
  }
}
