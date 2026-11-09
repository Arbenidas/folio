import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OnboardingPreferences {
  OnboardingPreferences._();

  static Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/folio_onboarding.json');
  }

  static Future<bool> tourCompleted() async {
    try {
      final file = await _file();
      if (!await file.exists()) return false;
      final value = jsonDecode(await file.readAsString());
      return value is Map && value['tourCompleted'] == true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setTourCompleted() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'tourCompleted': true}),
        flush: true,
      );
    } catch (_) {
      // The tour is still skippable if local preference storage is unavailable.
    }
  }
}
