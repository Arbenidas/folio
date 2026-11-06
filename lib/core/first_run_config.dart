import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class FirstRunConfig {
  const FirstRunConfig({
    required this.isComplete,
    required this.notesDirectory,
  });

  final bool isComplete;
  final Directory notesDirectory;

  static const _channel = MethodChannel('apuntes/keyboard');
  static const _timeout = Duration(seconds: 4);

  static Future<FirstRunConfig> load() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final defaultDirectory = Directory('${supportDirectory.path}/cuaderno');
    final local = await _readLocal(supportDirectory);
    Map<String, Object?>? values;
    try {
      values = await _channel
          .invokeMapMethod<String, Object?>('loadInitialSetup')
          .timeout(_timeout);
    } catch (_) {
      values = null;
    }
    final selectedPath =
        values?['notesDirectory'] as String? ??
        local?['notesDirectory'] as String?;
    return FirstRunConfig(
      isComplete:
          (values?['isComplete'] as bool? ?? false) ||
          (local?['isComplete'] as bool? ?? false),
      notesDirectory: Directory(selectedPath ?? defaultDirectory.path),
    );
  }

  // This call remains open while the user navigates the native folder picker.
  // A short timeout here incorrectly reported an error during normal use.
  static Future<String?> chooseNotesDirectory(String currentPath) =>
      _channel.invokeMethod<String>('chooseNotesDirectory', currentPath);

  static Future<void> finish(String directoryPath) async {
    final supportDirectory = await getApplicationSupportDirectory();
    var savedNatively = false;
    try {
      await _channel
          .invokeMethod<void>('completeInitialSetup', directoryPath)
          .timeout(_timeout);
      savedNatively = true;
    } catch (_) {
      // Keep a local fallback so a stalled platform channel cannot trap the
      // user in the first-run screen. Native bookmarks are still preferred
      // whenever the macOS channel is available.
    }
    if (!savedNatively) {
      final config = File('${supportDirectory.path}/folio_initial_setup.json');
      await config.writeAsString(
        jsonEncode({'isComplete': true, 'notesDirectory': directoryPath}),
        flush: true,
      );
    }
  }

  /// Commits a folder change in Settings. Unlike first-run setup, this must
  /// fail closed so the editor never switches to a folder whose bookmark
  /// macOS did not persist.
  static Future<void> persistNotesDirectory(String directoryPath) => _channel
      .invokeMethod<void>('completeInitialSetup', directoryPath)
      .timeout(_timeout);

  static Future<Map<String, Object?>?> _readLocal(Directory support) async {
    try {
      final file = File('${support.path}/folio_initial_setup.json');
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, dynamic>) return value;
    } catch (_) {}
    return null;
  }
}

class NotesStorage {
  NotesStorage._();

  static Directory? directory;
}
