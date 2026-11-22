import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/finance_models.dart';

/// Persists Folio's money tracker completely isolated from Markdown notes
/// inside the application support directory (`folio_finances.json`), with
/// automatic atomic writes and a rotating `.bak` safety backup.
class FinanceRepository {
  FinanceRepository({Directory? directory}) : _overrideDirectory = directory;

  final Directory? _overrideDirectory;
  File? _cachedFile;

  Future<File?> _resolveFile() async {
    if (_cachedFile != null) return _cachedFile;
    if (_overrideDirectory != null) {
      _cachedFile = File(p.join(_overrideDirectory.path, 'folio_finances.json'));
      return _cachedFile;
    }
    try {
      final support = await getApplicationSupportDirectory();
      _cachedFile = File(p.join(support.path, 'folio_finances.json'));
      return _cachedFile;
    } catch (_) {
      return null;
    }
  }

  File _backupFileFor(File primary) => File('${primary.path}.bak');

  Future<FinanceSnapshot?> _tryRead(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        return FinanceSnapshot.fromJson(raw);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<FinanceSnapshot> load() async {
    final file = await _resolveFile();
    if (file == null) return FinanceSnapshot.starter();
    final primary = await _tryRead(file);
    if (primary != null) return primary;
    final backup = await _tryRead(_backupFileFor(file));
    if (backup != null) return backup;
    return FinanceSnapshot.starter();
  }

  Future<void> save(FinanceSnapshot snapshot) async {
    final file = await _resolveFile();
    if (file == null) return;
    await file.parent.create(recursive: true);

    // Keep previous valid snapshot as a `.bak` safety copy before overwriting.
    if (await file.exists()) {
      try {
        await file.copy(_backupFileFor(file).path);
      } catch (_) {}
    }

    final random = Random.secure();
    final temporary = File(
      p.join(
        file.parent.path,
        '.folio-write-finances-$pid-${random.nextInt(1 << 32)}',
      ),
    );
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
