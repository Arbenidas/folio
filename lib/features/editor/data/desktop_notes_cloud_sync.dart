import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../domain/document_repository.dart';
import '../domain/markdown_document.dart';
import '../domain/notebook_snapshot.dart';

class DecodedCloudNote {
  const DecodedCloudNote({
    required this.title,
    required this.content,
    required this.updatedAtMs,
    this.folder,
  });

  final String title;
  final String content;
  final int updatedAtMs;
  final String? folder;
}

class DecodedCloudNotebook {
  const DecodedCloudNotebook({
    required this.folders,
    required this.notes,
    required this.isDefaultStarterOnly,
  });

  final Set<String> folders;
  final List<DecodedCloudNote> notes;
  final bool isDefaultStarterOnly;
}

/// Shared envelope helpers matching `CrossPlatformNotesWorkspace` (`folio_notebook_v1`)
/// so macOS desktop `.md` folders/notes and Web/Mobile notes sync seamlessly in Firestore.
class FolioNotebookCloudCodec {
  static const String envelopeFormat = 'folio_notebook_v1';

  static String? normalizeFolderPath(String? raw) {
    if (raw == null) return null;
    final parts = raw
        .replaceAll('\\', '/')
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('/');
  }

  static String noteLookupKey(String? folder, String title) {
    final normFolder = normalizeFolderPath(folder)?.toLowerCase() ?? '';
    final normTitle = title.trim().toLowerCase();
    return '$normFolder::$normTitle';
  }

  /// Encodes a desktop notebook into the `folio_notebook_v1` JSON string.
  static String encodeDesktop({
    required List<MarkdownDocument> notes,
    required Set<String> folderPaths,
    int? nowMs,
  }) {
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final allFolders = <String>{};
    for (final raw in folderPaths) {
      final norm = normalizeFolderPath(raw);
      if (norm != null) allFolders.add(norm);
    }
    for (final note in notes) {
      final norm = normalizeFolderPath(note.folder);
      if (norm != null) allFolders.add(norm);
    }
    final sortedFolders = allFolders.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final sortedNotes = [...notes]
      ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));

    return jsonEncode({
      'format': envelopeFormat,
      'folders': [
        for (final path in sortedFolders) {'id': 'path:$path', 'name': path},
      ],
      'notes': [
        for (final doc in sortedNotes)
          {
            'id': doc.id,
            'title': doc.title,
            'content': doc.content,
            'updatedAtMs': ts,
            if (normalizeFolderPath(doc.folder) case final folder?)
              'folderId': 'path:$folder',
          },
      ],
    });
  }

  /// Decodes a `folio_notebook_v1` JSON string (or legacy plain markdown) into folders & notes.
  static DecodedCloudNotebook? decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['format'] == envelopeFormat) {
        final rawFolders = decoded['folders'] as List<dynamic>? ?? const [];
        final rawNotes = decoded['notes'] as List<dynamic>? ?? const [];

        final idToFolderPath = <String, String>{};
        final folderPaths = <String>{};
        final folderIds = <String>{};
        for (final entry in rawFolders) {
          if (entry is! Map<String, dynamic>) continue;
          final id = entry['id'] as String?;
          final name = normalizeFolderPath(entry['name'] as String?);
          if (id != null) folderIds.add(id);
          if (id != null && name != null) {
            idToFolderPath[id] = name;
            folderPaths.add(name);
          }
        }

        final notes = <DecodedCloudNote>[];
        final noteIds = <String>{};
        for (final entry in rawNotes) {
          if (entry is! Map<String, dynamic>) continue;
          final id = entry['id'] as String? ?? '';
          if (id.isNotEmpty) noteIds.add(id);
          final title = (entry['title'] as String? ?? 'Sin título').trim();
          final content = entry['content'] as String? ?? '';
          final updatedAtMs = (entry['updatedAtMs'] as num?)?.toInt() ?? 0;
          final folderId = entry['folderId'] as String?;
          final folder = folderId != null
              ? idToFolderPath[folderId] ??
                    (folderId.startsWith('path:')
                        ? normalizeFolderPath(folderId.substring(5))
                        : null)
              : null;
          if (folder != null) folderPaths.add(folder);
          notes.add(
            DecodedCloudNote(
              title: title.isEmpty ? 'Sin título' : title,
              content: content,
              updatedAtMs: updatedAtMs,
              folder: folder,
            ),
          );
        }

        const starterNoteIds = {'note-welcome', 'note-ideas'};
        const starterFolderIds = {'fld-personal', 'fld-work'};
        final isStarterOnly =
            noteIds.isNotEmpty &&
            noteIds.every(starterNoteIds.contains) &&
            folderIds.every(starterFolderIds.contains);

        return DecodedCloudNotebook(
          folders: folderPaths,
          notes: notes,
          isDefaultStarterOnly: isStarterOnly,
        );
      }
    } catch (_) {
      // Fall through to legacy plain-markdown scratchpad if non-JSON
    }
    return null;
  }

  /// Order-independent content signature used to prevent echo upload loops.
  static String signatureFor({
    required List<MarkdownDocument> notes,
    required Set<String> folderPaths,
  }) {
    final normFolders =
        folderPaths
            .map(normalizeFolderPath)
            .whereType<String>()
            .map((s) => s.toLowerCase())
            .toSet()
            .toList()
          ..sort();
    final normNotes =
        notes
            .map((n) => '${noteLookupKey(n.folder, n.title)}=${n.content}')
            .toList()
          ..sort();
    return jsonEncode({'f': normFolders, 'n': normNotes});
  }

  static String signatureForDecoded(DecodedCloudNotebook decoded) {
    final normFolders =
        decoded.folders
            .map(normalizeFolderPath)
            .whereType<String>()
            .map((s) => s.toLowerCase())
            .toSet()
            .toList()
          ..sort();
    final normNotes =
        decoded.notes
            .map((n) => '${noteLookupKey(n.folder, n.title)}=${n.content}')
            .toList()
          ..sort();
    return jsonEncode({'f': normFolders, 'n': normNotes});
  }
}

/// Real-time bidirectional Firestore sync bridge for desktop `EditorNotifier`.
class DesktopNotesCloudSync {
  DesktopNotesCloudSync({
    required this.cloudSync,
    required this.getRepository,
    required this.getCurrentSnapshot,
    required this.isNoteDirty,
    required this.onRemoteApplied,
  });

  final FolioCloudSyncService cloudSync;
  final DocumentRepository Function() getRepository;
  final NotebookSnapshot Function() getCurrentSnapshot;
  final bool Function(String noteId) isNoteDirty;
  final Future<void> Function() onRemoteApplied;

  StreamSubscription<RemoteScratchpadPayload?>? _sub;
  Timer? _uploadDebounce;
  bool _started = false;
  bool _disposed = false;
  bool _applyingRemote = false;
  bool _hasCompletedInitialSync = false;
  int _lastCloudUpdatedMs = 0;
  String? _lastCloudSignature;
  Set<String> _syncedNoteKeys = {};

  void start() {
    if (_started || _disposed) return;
    _started = true;
    cloudSync.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    if (_disposed) return;
    if (!cloudSync.isSignedIn) {
      unawaited(_sub?.cancel());
      _sub = null;
      _hasCompletedInitialSync = false;
      _lastCloudUpdatedMs = 0;
      _lastCloudSignature = null;
      _syncedNoteKeys = {};
      return;
    }
    if (_sub == null) {
      unawaited(_initialSyncAndWatch());
    }
  }

  Future<void> _initialSyncAndWatch() async {
    if (_disposed || !cloudSync.isSignedIn) return;
    try {
      final remote = await cloudSync.fetchScratchpad();
      if (_disposed || !cloudSync.isSignedIn) return;

      final local = getCurrentSnapshot();
      final decoded = remote != null
          ? FolioNotebookCloudCodec.decode(remote.content)
          : null;
      final localHasContent =
          local.notes.isNotEmpty || local.folderPaths.isNotEmpty;

      if (decoded == null ||
          (decoded.isDefaultStarterOnly && localHasContent)) {
        // Cloud is empty or only has Web's untouched starter template:
        // push desktop's real folders & notes up to Firestore immediately.
        await _uploadCurrentSnapshot();
      } else {
        // Merge remote notes/folders into desktop without deleting local notes.
        final remoteSignature = FolioNotebookCloudCodec.signatureForDecoded(
          decoded,
        );
        final localSignature = FolioNotebookCloudCodec.signatureFor(
          notes: local.notes,
          folderPaths: local.folderPaths,
        );
        _lastCloudUpdatedMs = remote!.updatedAtMs;
        if (remoteSignature != localSignature) {
          await _applyRemoteToDisk(decoded, allowDeletions: false);
          final afterMerge = getCurrentSnapshot();
          final mergedSig = FolioNotebookCloudCodec.signatureFor(
            notes: afterMerge.notes,
            folderPaths: afterMerge.folderPaths,
          );
          _lastCloudSignature = mergedSig;
          _rememberSyncedKeys(afterMerge);
          // If desktop had extra notes/folders not yet on Web, push the union!
          if (mergedSig != remoteSignature) {
            await _uploadCurrentSnapshot();
          }
        } else {
          _lastCloudSignature = remoteSignature;
          _rememberSyncedKeys(local);
        }
      }
      _hasCompletedInitialSync = true;
    } catch (e) {
      debugPrint('DesktopNotesCloudSync initial sync error: $e');
    }

    if (_disposed || !cloudSync.isSignedIn) return;
    _sub ??= cloudSync.watchScratchpad().listen(
      (remote) {
        if (remote == null || _disposed || _applyingRemote) return;
        if (remote.updatedAtMs <= _lastCloudUpdatedMs) return;
        final decoded = FolioNotebookCloudCodec.decode(remote.content);
        if (decoded == null) return;
        final remoteSig = FolioNotebookCloudCodec.signatureForDecoded(decoded);
        if (remoteSig == _lastCloudSignature) {
          _lastCloudUpdatedMs = remote.updatedAtMs;
          return;
        }
        _lastCloudUpdatedMs = remote.updatedAtMs;
        unawaited(_handleRealtimeRemote(decoded, remoteSig));
      },
      onError: (Object e) {
        debugPrint('DesktopNotesCloudSync stream error: $e');
      },
    );
  }

  Future<void> _handleRealtimeRemote(
    DecodedCloudNotebook decoded,
    String remoteSig,
  ) async {
    try {
      await _applyRemoteToDisk(
        decoded,
        allowDeletions: _hasCompletedInitialSync,
      );
      _lastCloudSignature = remoteSig;
      _rememberSyncedKeys(getCurrentSnapshot());
    } catch (e) {
      debugPrint('DesktopNotesCloudSync realtime apply error: $e');
    }
  }

  Future<void> _applyRemoteToDisk(
    DecodedCloudNotebook decoded, {
    required bool allowDeletions,
  }) async {
    if (_disposed || _applyingRemote) return;
    _applyingRemote = true;
    try {
      final repo = getRepository();
      var disk = await repo.scan();
      var changed = false;

      // 1. Ensure all remote folders exist on disk (case-insensitive check)
      final existingFoldersLower = disk.folderPaths
          .map((f) => FolioNotebookCloudCodec.normalizeFolderPath(f) ?? f)
          .map((f) => f.toLowerCase())
          .toSet();
      final sortedRemoteFolders = decoded.folders.toList()
        ..sort((a, b) => a.length.compareTo(b.length));
      for (final folder in sortedRemoteFolders) {
        final norm = FolioNotebookCloudCodec.normalizeFolderPath(folder);
        if (norm == null) continue;
        if (!existingFoldersLower.contains(norm.toLowerCase())) {
          try {
            await repo.createFolder(norm);
            existingFoldersLower.add(norm.toLowerCase());
            changed = true;
          } catch (_) {}
        }
      }

      if (changed) {
        disk = await repo.scan();
      }

      // 2. Upsert all remote notes
      final diskByKey = <String, MarkdownDocument>{
        for (final doc in disk.notes)
          FolioNotebookCloudCodec.noteLookupKey(doc.folder, doc.title): doc,
      };
      final remoteKeys = <String>{};

      for (final remoteNote in decoded.notes) {
        final key = FolioNotebookCloudCodec.noteLookupKey(
          remoteNote.folder,
          remoteNote.title,
        );
        remoteKeys.add(key);
        final existing = diskByKey[key];
        if (existing != null) {
          if (existing.content != remoteNote.content &&
              !isNoteDirty(existing.id)) {
            await repo.saveNote(existing.copyWith(content: remoteNote.content));
            changed = true;
          }
        } else {
          await repo.createNote(
            title: remoteNote.title,
            folder: remoteNote.folder,
            content: remoteNote.content,
          );
          changed = true;
        }
      }

      // 3. Mirror deletions ONLY for notes that were previously synced
      //    and removed in a newer remote edit (moved safely to Trash!).
      if (allowDeletions && _syncedNoteKeys.isNotEmpty) {
        for (final doc in disk.notes) {
          final key = FolioNotebookCloudCodec.noteLookupKey(
            doc.folder,
            doc.title,
          );
          if (_syncedNoteKeys.contains(key) &&
              !remoteKeys.contains(key) &&
              !isNoteDirty(doc.id)) {
            try {
              await repo.deleteNote(doc.id);
              changed = true;
            } catch (_) {}
          }
        }
      }

      if (changed && !_disposed) {
        await onRemoteApplied();
      }
    } finally {
      _applyingRemote = false;
    }
  }

  /// Schedules a debounced upload of the desktop notebook to Firestore.
  void scheduleUpload() {
    if (_disposed || _applyingRemote || !cloudSync.isSignedIn) return;
    _uploadDebounce?.cancel();
    _uploadDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_uploadCurrentSnapshot());
    });
  }

  Future<void> _uploadCurrentSnapshot() async {
    if (_disposed || _applyingRemote || !cloudSync.isSignedIn) return;
    final snap = getCurrentSnapshot();
    final sig = FolioNotebookCloudCodec.signatureFor(
      notes: snap.notes,
      folderPaths: snap.folderPaths,
    );
    if (sig == _lastCloudSignature) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final encoded = FolioNotebookCloudCodec.encodeDesktop(
      notes: snap.notes,
      folderPaths: snap.folderPaths,
      nowMs: nowMs,
    );
    if (encoded.length > 200000) {
      debugPrint(
        'DesktopNotesCloudSync: payload (${encoded.length} bytes) exceeds 200 KB limit.',
      );
      return;
    }
    _lastCloudUpdatedMs = nowMs;
    _lastCloudSignature = sig;
    _rememberSyncedKeys(snap);
    await cloudSync.uploadScratchpad(encoded, updatedAtMs: nowMs);
  }

  void _rememberSyncedKeys(NotebookSnapshot snap) {
    _syncedNoteKeys = {
      for (final doc in snap.notes)
        FolioNotebookCloudCodec.noteLookupKey(doc.folder, doc.title),
    };
  }

  Future<void> dispose() async {
    _disposed = true;
    _uploadDebounce?.cancel();
    cloudSync.removeListener(_onAuthChanged);
    await _sub?.cancel();
    _sub = null;
  }
}
