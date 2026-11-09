import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class VimPreferences {
  const VimPreferences({required this.enabled, required this.lastSearch});

  final bool enabled;
  final String lastSearch;

  static Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/folio_vim_preferences.json');
  }

  static Future<VimPreferences> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return const VimPreferences(enabled: false, lastSearch: '');
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) {
        return const VimPreferences(enabled: false, lastSearch: '');
      }
      return VimPreferences(
        enabled: value['enabled'] == true,
        lastSearch: value['lastSearch'] is String
            ? value['lastSearch'] as String
            : '',
      );
    } catch (_) {
      return const VimPreferences(enabled: false, lastSearch: '');
    }
  }

  static Future<void> save({
    required bool enabled,
    required String lastSearch,
  }) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'enabled': enabled, 'lastSearch': lastSearch}),
        flush: true,
      );
    } catch (_) {
      // Vim remains usable for this session when preferences cannot be saved.
    }
  }
}
