import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RecoveredDraft {
  const RecoveredDraft({
    required this.id,
    required this.title,
    required this.recoveredAt,
    required this.content,
  });

  final String id;
  final String title;
  final DateTime recoveredAt;
  final String content;
}

class RecoveredDraftsRepository {
  RecoveredDraftsRepository({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<Directory> _root() async {
    final support = _directory ?? await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'Folio', 'Recovered drafts'));
    await root.create(recursive: true);
    return root;
  }

  Future<RecoveredDraft> save({
    required String title,
    required String content,
  }) async {
    final root = await _root();
    final recoveredAt = DateTime.now();
    final stamp = recoveredAt.toUtc().toIso8601String().replaceAll(':', '-');
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\.+$'), '');
    final base = '$stamp - ${safeTitle.isEmpty ? 'Nota' : safeTitle}';
    var file = File(p.join(root.path, '$base.md'));
    var suffix = 2;
    while (await file.exists()) {
      file = File(p.join(root.path, '$base $suffix.md'));
      suffix++;
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
    return RecoveredDraft(
      id: file.path,
      title: title,
      recoveredAt: recoveredAt,
      content: content,
    );
  }

  Future<List<RecoveredDraft>> list() async {
    final root = await _root();
    final drafts = <RecoveredDraft>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.md')) continue;
      try {
        final name = p.basenameWithoutExtension(entry.path);
        final separator = name.indexOf(' - ');
        final title = separator < 0 ? name : name.substring(separator + 3);
        final recoveredAt = (await entry.stat()).modified;
        drafts.add(
          RecoveredDraft(
            id: entry.path,
            title: title,
            recoveredAt: recoveredAt,
            content: await entry.readAsString(),
          ),
        );
      } on FileSystemException {
        // A draft that disappears while the list is being built is skipped.
      }
    }
    drafts.sort((a, b) => b.recoveredAt.compareTo(a.recoveredAt));
    return drafts;
  }

  Future<void> delete(String id) async {
    final root = await _root();
    final file = File(id);
    if (!p.isWithin(
      p.normalize(p.absolute(root.path)),
      p.normalize(p.absolute(file.path)),
    )) {
      throw const FileSystemException('La recuperación no pertenece a Folio.');
    }
    if (await file.exists()) await file.delete();
  }
}
