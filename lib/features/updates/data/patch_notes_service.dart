import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppVersionInfo {
  const AppVersionInfo._();

  static const String repository = 'Arbenidas/folio';
  static const String currentVersion = String.fromEnvironment(
    'FOLIO_APP_VERSION',
    defaultValue: '0.1.0-alpha.6',
  );
  static const int currentBuild = int.fromEnvironment(
    'FOLIO_APP_BUILD',
    defaultValue: 6,
  );

  static const String updatesManifestUrl =
      'https://raw.githubusercontent.com/$repository/updates/updates.json';
  static const String remotePatchNotesUrl =
      'https://raw.githubusercontent.com/$repository/updates/patch_notes.json';
  static const String fallbackPatchNotesUrl =
      'https://raw.githubusercontent.com/$repository/main/assets/patch_notes.json';
  static const String defaultAndroidApkUrl =
      'https://github.com/$repository/releases/download/mobile-latest/Folio-android.apk';
  static const String defaultReleasesUrl =
      'https://github.com/$repository/releases';
  static const String defaultWebUrl = 'https://folio-2b7e3.web.app/';
}

class PatchNoteEntry {
  const PatchNoteEntry({
    required this.version,
    required this.build,
    required this.date,
    required this.title,
    this.tag = '',
    this.highlights = const [],
    this.fixes = const [],
  });

  final String version;
  final int build;
  final String date;
  final String title;
  final String tag;
  final List<String> highlights;
  final List<String> fixes;

  factory PatchNoteEntry.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return PatchNoteEntry(
      version: map['version'] as String? ?? '0.0.0',
      build: (map['build'] as num?)?.toInt() ?? 0,
      date: map['date'] as String? ?? '',
      title: map['title'] as String? ?? '',
      tag: map['tag'] as String? ?? '',
      highlights: [
        for (final item in (map['highlights'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
      fixes: [
        for (final item in (map['fixes'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
    );
  }
}

class RemoteUpdateManifest {
  const RemoteUpdateManifest({
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.commitSha,
    required this.androidApkUrl,
    required this.macosUrl,
    required this.webUrl,
    this.summary = '',
  });

  final String version;
  final int build;
  final String publishedAt;
  final String commitSha;
  final String androidApkUrl;
  final String macosUrl;
  final String webUrl;
  final String summary;

  bool get isNewerThanCurrent => build > AppVersionInfo.currentBuild;

  factory RemoteUpdateManifest.fromJson(Map<String, dynamic> map) {
    return RemoteUpdateManifest(
      version: map['version'] as String? ?? AppVersionInfo.currentVersion,
      build: (map['build'] as num?)?.toInt() ?? 0,
      publishedAt: map['publishedAt'] as String? ?? '',
      commitSha: map['commitSha'] as String? ?? '',
      androidApkUrl:
          map['androidApkUrl'] as String? ?? AppVersionInfo.defaultAndroidApkUrl,
      macosUrl: map['macosUrl'] as String? ?? AppVersionInfo.defaultReleasesUrl,
      webUrl: map['webUrl'] as String? ?? AppVersionInfo.defaultWebUrl,
      summary: map['summary'] as String? ?? '',
    );
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.notes,
    this.manifest,
    this.error,
    this.checkedRemote = false,
  });

  final List<PatchNoteEntry> notes;
  final RemoteUpdateManifest? manifest;
  final String? error;
  final bool checkedRemote;

  bool get hasUpdate => manifest?.isNewerThanCurrent == true;
}

class PatchNotesService {
  PatchNotesService({http.Client? client}) : _client = client ?? http.Client();

  static final PatchNotesService instance = PatchNotesService();
  static const _seenBuildKey = 'folio_last_seen_patch_build';

  final http.Client _client;

  Future<List<PatchNoteEntry>> loadBundledNotes() async {
    try {
      final raw = await rootBundle.loadString('assets/patch_notes.json');
      return _parseNotes(raw);
    } catch (_) {
      return const [];
    }
  }

  List<PatchNoteEntry> _parseNotes(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final entries = [for (final item in decoded) PatchNoteEntry.fromJson(item)];
    entries.sort((a, b) => b.build.compareTo(a.build));
    return entries;
  }

  Future<UpdateCheckResult> checkForUpdates({
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final bundled = await loadBundledNotes();
    RemoteUpdateManifest? manifest;
    List<PatchNoteEntry> mergedNotes = bundled;
    String? error;
    var checkedRemote = false;

    try {
      final manifestResp = await _client
          .get(Uri.parse(AppVersionInfo.updatesManifestUrl))
          .timeout(timeout);
      if (manifestResp.statusCode == 200) {
        final decoded = jsonDecode(manifestResp.body);
        if (decoded is Map<String, dynamic>) {
          manifest = RemoteUpdateManifest.fromJson(decoded);
          checkedRemote = true;
        }
      }
    } catch (e) {
      error = e.toString();
    }

    // Also pull latest remote patch_notes.json so newly pushed notes appear live
    for (final url in const [
      AppVersionInfo.remotePatchNotesUrl,
      AppVersionInfo.fallbackPatchNotesUrl,
    ]) {
      try {
        final notesResp = await _client.get(Uri.parse(url)).timeout(timeout);
        if (notesResp.statusCode == 200) {
          final remoteNotes = _parseNotes(notesResp.body);
          if (remoteNotes.isNotEmpty) {
            mergedNotes = _mergeNotes(remoteNotes, bundled);
            checkedRemote = true;
            break;
          }
        }
      } catch (_) {
        // Try fallback URL or stay with bundled notes
      }
    }

    return UpdateCheckResult(
      notes: mergedNotes,
      manifest: manifest,
      error: checkedRemote ? null : error,
      checkedRemote: checkedRemote,
    );
  }

  List<PatchNoteEntry> _mergeNotes(
    List<PatchNoteEntry> primary,
    List<PatchNoteEntry> fallback,
  ) {
    final byVersion = <String, PatchNoteEntry>{};
    for (final item in fallback) {
      byVersion['${item.version}+${item.build}'] = item;
    }
    for (final item in primary) {
      byVersion['${item.version}+${item.build}'] = item;
    }
    final list = byVersion.values.toList()
      ..sort((a, b) => b.build.compareTo(a.build));
    return list;
  }

  Future<bool> hasUnreadPatchNotes(int latestBuild) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_seenBuildKey) ?? 0;
      return latestBuild > seen;
    } catch (_) {
      return false;
    }
  }

  Future<void> markPatchNotesSeen(int build) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenBuildKey, build);
    } catch (_) {}
  }

  String downloadUrlForCurrentPlatform(RemoteUpdateManifest? manifest) {
    if (kIsWeb) {
      return manifest?.webUrl ?? AppVersionInfo.defaultWebUrl;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return manifest?.androidApkUrl ?? AppVersionInfo.defaultAndroidApkUrl;
      case TargetPlatform.macOS:
        return manifest?.macosUrl ?? AppVersionInfo.defaultReleasesUrl;
      case TargetPlatform.iOS:
        return manifest?.webUrl ?? AppVersionInfo.defaultReleasesUrl;
      default:
        return manifest?.macosUrl ?? AppVersionInfo.defaultReleasesUrl;
    }
  }

  String downloadLabelForCurrentPlatform() {
    if (kIsWeb) return 'Abrir versión Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Descargar APK';
      case TargetPlatform.macOS:
        return 'Descargar para macOS';
      case TargetPlatform.iOS:
        return 'Ver versión Web / Releases';
      default:
        return 'Descargar actualización';
    }
  }
}
