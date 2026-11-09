import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;

/// Each folder keeps its attachments beside its Markdown files.
abstract final class NotebookAttachments {
  static const directoryName = '.folio-assets';
  static const maxBytes = 20 * 1024 * 1024;
  static final _reference = RegExp(r'\.folio-assets/[a-f0-9]{32}\.png');
  static final _random = Random.secure();

  static Set<String> references(String markdown) =>
      _reference.allMatches(markdown).map((match) => match.group(0)!).toSet();

  static Future<Directory?> _directory(
    Directory parent, {
    bool create = false,
  }) async {
    final directory = Directory(p.join(parent.path, directoryName));
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.directory) return directory;
    if (type == FileSystemEntityType.notFound) {
      return create ? directory.create() : null;
    }
    throw FileSystemException(
      'La carpeta de imágenes no es una carpeta normal.',
      directory.path,
    );
  }

  static Future<String> write(Directory parent, Uint8List png) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (png.length > maxBytes ||
        png.length <= signature.length ||
        !listEquals(png.sublist(0, signature.length), signature)) {
      throw const FormatException('Pega una imagen PNG de hasta 20 MB.');
    }
    final name = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final directory = (await _directory(parent, create: true))!;
    await _write(directory, '$name.png', png);
    return '$directoryName/$name.png';
  }

  static Future<Uint8List?> read(Directory parent, String reference) async {
    if (_reference.stringMatch(reference) != reference) return null;
    final directory = await _directory(parent);
    if (directory == null) return null;
    final file = File(p.join(directory.path, p.posix.basename(reference)));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxBytes) {
      return null;
    }
    return file.readAsBytes();
  }

  static Future<void> copyReferenced(
    Directory source,
    Directory target,
    String markdown,
  ) async {
    if (p.equals(source.path, target.path)) return;
    for (final reference in references(markdown)) {
      final bytes = await read(source, reference);
      if (bytes == null) continue;
      final existing = await read(target, reference);
      if (existing != null && listEquals(bytes, existing)) continue;
      final directory = (await _directory(target, create: true))!;
      await _write(directory, p.posix.basename(reference), bytes);
    }
  }

  static Future<void> _write(
    Directory directory,
    String name,
    Uint8List bytes,
  ) async {
    final file = File(p.join(directory.path, name));
    await file.create(exclusive: true);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await file.delete();
      rethrow;
    }
  }
}
