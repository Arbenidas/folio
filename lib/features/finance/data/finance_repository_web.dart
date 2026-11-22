import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_models.dart';

/// Web storage implementation for Folio's money tracker using browser
/// SharedPreferences (localStorage) with an automatic backup key.
class FinanceRepository {
  FinanceRepository({Object? directory});

  static const _primaryKey = 'folio_finances_json_v1';
  static const _backupKey = 'folio_finances_json_v1_bak';

  FinanceSnapshot? _tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return FinanceSnapshot.fromJson(parsed);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<FinanceSnapshot> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final primary = _tryDecode(prefs.getString(_primaryKey));
      if (primary != null) return primary;
      final backup = _tryDecode(prefs.getString(_backupKey));
      if (backup != null) return backup;
    } catch (_) {}
    return FinanceSnapshot.starter();
  }

  Future<void> save(FinanceSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(_primaryKey);
      if (prev != null && prev.isNotEmpty) {
        await prefs.setString(_backupKey, prev);
      }
      await prefs.setString(_primaryKey, jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }
}
