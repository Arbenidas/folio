import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/document_repository.dart';
import '../domain/markdown_document.dart';
import '../domain/notebook_snapshot.dart';
import '../domain/trashed_note.dart';
import 'notebook_attachments.dart';

class FileRepository implements DocumentRepository {
  FileRepository({this.directory});

  static const _trashFolder = '.folio-trash';

  /// The user-selected parent. The notebook itself lives in its `Folio` child.
  final Directory? directory;

  Future<Directory> _parent() async =>
      directory ?? await getApplicationSupportDirectory();

  Future<Directory> _root({bool create = true}) async {
    final root = Directory(p.join((await _parent()).path, 'Folio'));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.file) {
      throw FileSystemException(
        'La carpeta Folio no puede ser un enlace ni un archivo.',
        root.path,
      );
    }
    if (create && type == FileSystemEntityType.notFound)
      await root.create(recursive: true);
    return root;
  }

  String _idFor(File file, Directory root) => p.posix.normalize(
    p.relative(file.path, from: root.path).split(p.separator).join('/'),
  );

  String _safeSegment(String value, {String fallback = 'Nueva nota'}) {
    var safe = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
    if (safe.isEmpty || safe == '.' || safe == '..') safe = fallback;
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$',
      caseSensitive: false,
    ).hasMatch(safe)) {
      safe = '_$safe';
    }
    return safe;
  }

  String _safeNoteTitle(String value) {
    var title = _safeSegment(value);
    if (title.toLowerCase().endsWith('.md')) {
      title = title.substring(0, title.length - 3).trim();
    }
    return title.isEmpty ? 'Nueva nota' : title;
  }

  List<String> _safeFolderSegments(String? folder) =>
      folder == null || folder.isEmpty
      ? const []
      : folder
            .split('/')
            .where((part) => part.isNotEmpty)
            .map((part) => _safeSegment(part, fallback: 'Nueva carpeta'))
            .toList();

  File _fileFor(Directory root, String id) {
    final segments = id.split('/').where((part) => part.isNotEmpty).toList();
    final path = p.normalize(p.joinAll([root.path, ...segments]));
    if (!p.isWithin(root.path, path)) {
      throw const FileSystemException('La ruta de la nota sale de Folio.');
    }
    var parent = root;
    for (final segment in segments.take(segments.length - 1)) {
      parent = Directory(p.join(parent.path, segment));
      if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw FileSystemException(
          'La ruta atraviesa una carpeta no disponible o un enlace.',
          parent.path,
        );
      }
    }
    final fileType = FileSystemEntity.typeSync(path, followLinks: false);
    if (fileType == FileSystemEntityType.link ||
        fileType == FileSystemEntityType.directory) {
      throw FileSystemException('La nota no es un archivo normal.', path);
    }
    return File(path);
  }

  String _uniquePath(
    Directory parent,
    String base, {
    String extension = '.md',
  }) {
    var candidate = File(p.join(parent.path, '$base$extension'));
    var suffix = 2;
    while (FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      candidate = File(p.join(parent.path, '$base $suffix$extension'));
      suffix++;
    }
    return candidate.path;
  }

  String _uniqueFolderPath(Directory parent, String base) {
    var candidate = Directory(p.join(parent.path, base));
    var suffix = 2;
    while (FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      candidate = Directory(p.join(parent.path, '$base $suffix'));
      suffix++;
    }
    return candidate.path;
  }

  Future<Directory> _ensureNoteFolder(
    Directory root,
    List<String> segments,
  ) async {
    var current = root;
    for (final segment in segments) {
      final next = Directory(p.join(current.path, segment));
      final type = await FileSystemEntity.type(next.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        current = next;
      } else if (type == FileSystemEntityType.notFound) {
        current = await next.create();
      } else {
        throw FileSystemException(
          'La ruta contiene un archivo o enlace y no se puede usar como carpeta.',
          next.path,
        );
      }
    }
    return current;
  }

  Future<void> _writeAtomically(File file, String content) async {
    await file.parent.create(recursive: true);
    final temp = File(
      p.join(
        file.parent.path,
        '.folio-write-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temp.writeAsString(content, encoding: utf8, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<NotebookSnapshot> load() async {
    final root = await _root();
    return _scan(root);
  }

  @override
  Future<NotebookSnapshot> scan() async => _scan(await _root());

  Future<NotebookSnapshot> _scan(Directory root) async {
    final notes = <MarkdownDocument>[];
    final folders = <String>{};
    final errors = <NotebookReadError>[];

    Future<void> visit(Directory directory, String relativeFolder) async {
      await for (final entry in directory.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;

        if (entry is Directory) {
          final folder = relativeFolder.isEmpty
              ? name
              : '$relativeFolder/$name';
          folders.add(folder);
          await visit(entry, folder);
          continue;
        }
        if (entry is! File || !name.toLowerCase().endsWith('.md')) continue;

        final id = _idFor(entry, root);
        final title = p.posix.basenameWithoutExtension(id);
        final slash = id.lastIndexOf('/');
        final folder = slash < 0 ? null : id.substring(0, slash);
        try {
          notes.add(
            MarkdownDocument(
              id: id,
              title: title,
              folder: folder,
              content: await entry.readAsString(encoding: utf8),
            ),
          );
        } on FileSystemException {
          errors.add(NotebookReadError(id, 'No se pudo leer el archivo.'));
        } on FormatException {
          errors.add(
            NotebookReadError(id, 'El archivo no contiene UTF-8 válido.'),
          );
        }
      }
    }

    await visit(root, '');
    notes.sort((a, b) {
      final folded = a.id.toLowerCase().compareTo(b.id.toLowerCase());
      return folded == 0 ? a.id.compareTo(b.id) : folded;
    });
    return NotebookSnapshot(
      notes: notes,
      folderPaths: folders,
      readErrors: errors,
    );
  }

  @override
  Stream<void> watch() async* {
    final root = await _root();
    yield* root
        .watch(recursive: true)
        .where((event) => !p.basename(event.path).startsWith('.folio-write-'))
        .map((_) {});
  }

  @override
  Future<MarkdownDocument> createNote({
    String title = 'Nueva nota',
    String? folder,
    String content = '',
  }) async {
    final root = await _root();
    final parent = await _ensureNoteFolder(root, _safeFolderSegments(folder));
    final safeTitle = _safeNoteTitle(title);
    final path = _uniquePath(parent, safeTitle);
    final id = _idFor(File(path), root);
    await _writeAtomically(File(path), content);
    return MarkdownDocument(
      id: id,
      title: p.posix.basenameWithoutExtension(id),
      folder: _nullableFolder(id),
      content: content,
    );
  }

  @override
  Future<MarkdownDocument> saveNote(MarkdownDocument note) async {
    final file = _fileFor(await _root(), note.id);
    await _writeAtomically(file, note.content);
    return note;
  }

  @override
  Future<MarkdownDocument> renameNote(String id, String title) async {
    final root = await _root();
    final source = _fileFor(root, id);
    final parent = source.parent;
    final safeTitle = _safeNoteTitle(title);
    if (p.posix.basenameWithoutExtension(id) == safeTitle) {
      return _documentFor(source, root);
    }
    final targetPath = _uniquePath(parent, safeTitle);
    final target = File(targetPath);
    if (p.equals(source.path, target.path)) {
      return _documentFor(source, root);
    }
    await source.rename(target.path);
    return _documentFor(target, root);
  }

  @override
  Future<MarkdownDocument> moveNote(String id, String? folder) async {
    final root = await _root();
    final source = _fileFor(root, id);
    final targetParent = Directory(
      p.joinAll([root.path, ..._safeFolderSegments(folder)]),
    );
    await _ensureNoteFolder(root, _safeFolderSegments(folder));
    if (p.equals(source.parent.path, targetParent.path)) {
      return _documentFor(source, root);
    }
    final note = await _documentFor(source, root);
    await NotebookAttachments.copyReferenced(
      source.parent,
      targetParent,
      note.content,
    );
    final targetPath = _uniquePath(
      targetParent,
      p.posix.basenameWithoutExtension(id),
    );
    final target = await source.rename(targetPath);
    return _documentFor(target, root);
  }

  @override
  Future<void> deleteNote(String id) async {
    final root = await _root();
    final file = _fileFor(root, id);
    if (!await file.exists()) return;
    final note = await _documentFor(file, root);
    final trash = await _ensureNoteFolder(root, [_trashFolder]);
    final entry = await trash.createTemp('note-');
    try {
      final parent = await _ensureNoteFolder(
        entry,
        note.folder?.split('/') ?? const [],
      );
      await NotebookAttachments.copyReferenced(
        file.parent,
        parent,
        note.content,
      );
      await file.rename(p.join(parent.path, p.basename(file.path)));
    } catch (_) {
      await entry.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<List<TrashedNote>> listTrash() async {
    final root = await _root();
    final trash = Directory(p.join(root.path, _trashFolder));
    if (await FileSystemEntity.type(trash.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return [];
    }
    final entries = <({TrashedNote note, DateTime date})>[];
    await for (final entry in trash.list(followLinks: false)) {
      if (entry is! Directory || !p.basename(entry.path).startsWith('note-')) {
        continue;
      }
      for (final note in (await _scan(entry)).notes) {
        entries.add((
          note: TrashedNote(
            id: '${p.basename(entry.path)}/${note.id}',
            title: note.title,
            folder: note.folder,
          ),
          date: (await entry.stat()).modified,
        ));
      }
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries.map((entry) => entry.note).toList();
  }

  @override
  Future<MarkdownDocument> restoreDeletedNote(String trashId) async {
    final root = await _root();
    final separator = trashId.indexOf('/');
    if (separator < 0 ||
        !trashId.startsWith('note-') ||
        !trashId.toLowerCase().endsWith('.md') ||
        trashId
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FileSystemException('La nota no pertenece a la papelera.');
    }
    final originalId = trashId.substring(separator + 1);
    final source = _fileFor(root, '$_trashFolder/$trashId');
    final content = await source.readAsString(encoding: utf8);
    final parent = await _ensureNoteFolder(
      root,
      _nullableFolder(originalId)?.split('/') ?? const [],
    );
    await NotebookAttachments.copyReferenced(source.parent, parent, content);
    final path = _uniquePath(
      parent,
      p.posix.basenameWithoutExtension(originalId),
    );
    final restored = await source.rename(path);
    final entry = Directory(
      p.join(root.path, _trashFolder, trashId.substring(0, separator)),
    );
    try {
      await entry.delete(recursive: true);
    } on FileSystemException {
      // The note was already restored. Empty trash entries are ignored.
    }
    return _documentFor(restored, root);
  }

  @override
  Future<String> saveImage(String noteId, Uint8List png) async {
    final note = _fileFor(await _root(), noteId);
    if (!await note.exists()) {
      throw const FileSystemException('La nota ya no existe.');
    }
    return NotebookAttachments.write(note.parent, png);
  }

  @override
  Future<Uint8List?> readImage(String noteId, String reference) async {
    final note = _fileFor(await _root(create: false), noteId);
    return NotebookAttachments.read(note.parent, reference);
  }

  @override
  Future<String> createFolder(String path) async {
    final root = await _root();
    final parts = _safeFolderSegments(path);
    if (parts.isEmpty)
      throw const FileSystemException('Nombre de carpeta vacío.');
    var parent = root;
    final created = <String>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final next = Directory(p.join(parent.path, part));
      final type = await FileSystemEntity.type(next.path, followLinks: false);
      if (type == FileSystemEntityType.directory && index < parts.length - 1) {
        parent = next;
        created.add(part);
        continue;
      }
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'No se pueden crear carpetas dentro de enlaces simbólicos.',
          next.path,
        );
      }
      final path = _uniqueFolderPath(parent, part);
      final folder = await Directory(path).create();
      parent = folder;
      created.add(p.basename(path));
    }
    return created.join('/');
  }

  @override
  Future<String> renameFolder(String path, String title) async {
    final root = await _root();
    final segments = _safeFolderSegments(path);
    if (segments.isEmpty)
      throw const FileSystemException(
        'No se puede renombrar la raíz de Folio.',
      );
    final source = Directory(p.joinAll([root.path, ...segments]));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('No se encontró la carpeta.', source.path);
    }
    await _ensureNoteFolder(root, segments.take(segments.length - 1).toList());
    final parent = source.parent;
    final safeTitle = _safeSegment(title, fallback: 'Nueva carpeta');
    if (p.basename(source.path) == safeTitle) return segments.join('/');
    final target = Directory(_uniqueFolderPath(parent, safeTitle));
    await source.rename(target.path);
    return p.posix
        .relative(target.path, from: root.path)
        .split(p.separator)
        .join('/');
  }

  @override
  Future<String> moveFolder(String path, String? destination) async {
    final root = await _root();
    final source = Directory(
      p.joinAll([root.path, ..._safeFolderSegments(path)]),
    );
    final sourceType = await FileSystemEntity.type(
      source.path,
      followLinks: false,
    );
    if (sourceType != FileSystemEntityType.directory) {
      throw FileSystemException('No se encontró la carpeta.', source.path);
    }
    final targetParent = Directory(
      p.joinAll([root.path, ..._safeFolderSegments(destination)]),
    );
    if (!p.isWithin(root.path, targetParent.path) &&
        !p.equals(root.path, targetParent.path)) {
      throw const FileSystemException('La ruta de destino sale de Folio.');
    }
    if (p.equals(source.path, targetParent.path) ||
        p.isWithin(source.path, targetParent.path)) {
      throw const FileSystemException(
        'No se puede mover una carpeta dentro de sí misma.',
      );
    }
    await _ensureNoteFolder(root, _safeFolderSegments(destination));
    final targetPath = _uniqueFolderPath(
      targetParent,
      _safeSegment(p.basename(source.path), fallback: 'Nueva carpeta'),
    );
    await source.rename(targetPath);
    return p.posix
        .relative(targetPath, from: root.path)
        .split(p.separator)
        .join('/');
  }

  @override
  Future<void> deleteFolder(String path) async {
    final root = await _root();
    final folder = Directory(
      p.joinAll([root.path, ..._safeFolderSegments(path)]),
    );
    if (await FileSystemEntity.type(folder.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException(
        'No se encontró una carpeta normal.',
        folder.path,
      );
    }
    final segments = _safeFolderSegments(path);
    await _ensureNoteFolder(root, segments.take(segments.length - 1).toList());
    final parent = folder.parent;
    if (!p.isWithin(root.path, folder.path)) {
      throw const FileSystemException('La ruta de la carpeta sale de Folio.');
    }
    final attachments = <Directory>[];
    await for (final entry in folder.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is File) {
        final extension = p.extension(name);
        if (extension.toLowerCase() == '.md') {
          try {
            final content = await entry.readAsString(encoding: utf8);
            await NotebookAttachments.copyReferenced(folder, parent, content);
          } on FormatException {
            // Preserve externally created Markdown even if it cannot be decoded.
          }
        }
        final target = _uniquePath(
          parent,
          p.basenameWithoutExtension(name),
          extension: extension,
        );
        await entry.rename(target);
      } else if (entry is Directory) {
        if (name == NotebookAttachments.directoryName) {
          attachments.add(entry);
          continue;
        }
        final target = _uniqueFolderPath(parent, name);
        await entry.rename(target);
      }
    }
    for (final assets in attachments) {
      // Preserve files left behind by an edit or an external Markdown file.
      await assets.rename(
        _uniqueFolderPath(
          parent,
          '${NotebookAttachments.directoryName}-respaldo',
        ),
      );
    }
    await folder.delete();
  }

  static Future<NotebookSnapshot> copyNotebookInto(
    Directory destinationParent,
    NotebookSnapshot source, {
    FileRepository? sourceRepository,
  }) async {
    final target = FileRepository(directory: destinationParent);
    final root = await target._root();
    final mappedFolders = <String, String>{};
    for (final folder in source.folderPaths.toList()..sort()) {
      final parent = folder.contains('/')
          ? mappedFolders[folder.substring(0, folder.lastIndexOf('/'))]
          : null;
      final name = folder.split('/').last;
      final intended = parent == null ? name : '$parent/$name';
      final exact = Directory(
        p.joinAll([root.path, ...target._safeFolderSegments(intended)]),
      );
      mappedFolders[folder] = await exact.exists()
          ? intended
          : await target.createFolder(intended);
    }
    final sourceRoot = await sourceRepository?._root(create: false);
    for (final note in source.notes) {
      final folder = note.folder == null ? null : mappedFolders[note.folder];
      if (sourceRoot != null) {
        final sourceParent = target._fileFor(sourceRoot, note.id).parent;
        final targetParent = await target._ensureNoteFolder(
          root,
          target._safeFolderSegments(folder),
        );
        await NotebookAttachments.copyReferenced(
          sourceParent,
          targetParent,
          note.content,
        );
      }
      await target.createNote(
        title: note.title,
        folder: folder,
        content: note.content,
      );
    }
    if (sourceRoot != null) {
      for (final note in await sourceRepository!.listTrash()) {
        final file = target._fileFor(sourceRoot, '$_trashFolder/${note.id}');
        final content = await file.readAsString(encoding: utf8);
        final trash = await target._ensureNoteFolder(root, [_trashFolder]);
        final entry = await trash.createTemp('note-');
        try {
          final parent = await target._ensureNoteFolder(
            entry,
            note.folder?.split('/') ?? const [],
          );
          await NotebookAttachments.copyReferenced(
            file.parent,
            parent,
            content,
          );
          await target._writeAtomically(
            File(p.join(parent.path, p.basename(file.path))),
            content,
          );
        } catch (_) {
          await entry.delete(recursive: true);
          rethrow;
        }
      }
    }
    return target.scan();
  }

  String? _nullableFolder(String id) {
    final slash = id.lastIndexOf('/');
    return slash < 0 ? null : id.substring(0, slash);
  }

  Future<MarkdownDocument> _documentFor(File file, Directory root) async {
    final id = _idFor(file, root);
    return MarkdownDocument(
      id: id,
      title: p.posix.basenameWithoutExtension(id),
      folder: _nullableFolder(id),
      content: await file.readAsString(encoding: utf8),
    );
  }

  @override
  Future<MarkdownDocument?> importMarkdown() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
    );
    if (file == null) return null;
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream()) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Abre un archivo de hasta 1 MB.');
      }
    }
    return createNote(
      title: file.name.replaceFirst(
        RegExp(r'\.(md|markdown|txt)$', caseSensitive: false),
        '',
      ),
      content: utf8.decode(bytes),
    );
  }

  @override
  Future<bool> exportMarkdown(MarkdownDocument note) async {
    final title = _safeSegment(note.title);
    if (NotebookAttachments.references(note.content).isNotEmpty) {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Exportar nota e imágenes',
      );
      if (path == null) return false;
      final destination = Directory(path);
      final source = _fileFor(await _root(), note.id);
      await NotebookAttachments.copyReferenced(
        source.parent,
        destination,
        note.content,
      );
      await _writeAtomically(
        File(_uniquePath(destination, title)),
        note.content,
      );
      return true;
    }
    final path = await FilePicker.saveFile(
      fileName: '$title.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
      bytes: Uint8List.fromList(utf8.encode(note.content)),
    );
    return path != null;
  }
}
