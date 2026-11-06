import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/document_repository.dart';
import '../domain/markdown_document.dart';

class FileRepository implements DocumentRepository {
  FileRepository({this.directory});
  final Directory? directory;

  /// Copies notes from the app's existing default location before the user
  /// switches to a custom folder. The original file remains as a backup.
  static Future<void> preserveDefaultNotesIn(Directory destination) async {
    final support = await getApplicationSupportDirectory();
    final sourceDirectory = Directory('${support.path}/cuaderno');
    String normalize(String path) => path.replaceAll(RegExp(r'/+$'), '');
    if (normalize(sourceDirectory.path) == normalize(destination.path)) return;

    if (await FileRepository(directory: destination)
        ._markdownDirectory(destination)
        .exists()) {
      return;
    }
    final targetNotes = File('${destination.path}/notes.json');
    final targetLegacy = File('${destination.path}/notebook.json');
    if (await targetNotes.exists() || await targetLegacy.exists()) return;

    final sourceRepository = FileRepository(directory: sourceDirectory);
    if (await sourceRepository._markdownDirectory(sourceDirectory).exists()) {
      await FileRepository(directory: destination)
          .save(await sourceRepository.load());
      return;
    }

    final sourceNotes = File('${sourceDirectory.path}/notes.json');
    final sourceLegacy = File('${sourceDirectory.path}/notebook.json');
    final source = await sourceNotes.exists()
        ? sourceNotes
        : await sourceLegacy.exists()
        ? sourceLegacy
        : null;
    if (source == null) return;

    await destination.create(recursive: true);
    await source.copy(
      '${destination.path}/${source == sourceNotes ? 'notes.json' : 'notebook.json'}',
    );
  }

  /// Copies the active notebook into another folder. Existing notes there are
  /// merged, and ID collisions are preserved as separate "(copia)" notes.
  static Future<List<MarkdownDocument>> copyNotesInto(
    Directory destination,
    List<MarkdownDocument> currentNotes,
  ) async {
    final target = FileRepository(directory: destination);
    final destinationNotes = await target._loadStored() ?? <MarkdownDocument>[];

    final currentById = {for (final note in currentNotes) note.id: note};
    final merged = <MarkdownDocument>[];
    final usedIds = <String>{};
    String uniqueId() {
      var id = DateTime.now().microsecondsSinceEpoch.toString();
      while (usedIds.contains(id) || currentById.containsKey(id)) {
        id = '${DateTime.now().microsecondsSinceEpoch}-${usedIds.length}';
      }
      return id;
    }

    for (final note in destinationNotes) {
      final activeVersion = currentById[note.id];
      if (activeVersion != null &&
          (activeVersion.title != note.title ||
              activeVersion.content != note.content ||
              activeVersion.folder != note.folder)) {
        final copyId = uniqueId();
        usedIds.add(copyId);
        merged.add(
          MarkdownDocument(
            id: copyId,
            title: '${note.title} (copia)',
            content: note.content,
            folder: note.folder,
          ),
        );
      } else {
        usedIds.add(note.id);
        merged.add(note);
      }
    }

    for (final note in currentNotes) {
      if (usedIds.add(note.id)) merged.add(note);
    }

    await target.save(merged);
    return merged;
  }

  Future<Directory> _directory() async {
    final dir =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/cuaderno');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<List<MarkdownDocument>> load() async {
    return await _loadStored() ??
        [
          const MarkdownDocument(
            id: 'welcome',
            title: 'Mis apuntes',
            content: '# Mis apuntes\n\nUn espacio para guardar lo que voy aprendiendo.\n\n## Hoy aprendí\n\n- \n',
          ),
        ];
  }

  Directory _markdownDirectory(Directory root) =>
      Directory('${root.path}/Notas Folio');

  Future<List<MarkdownDocument>?> _loadStored() async {
    final dir = await _directory();
    final markdown = _markdownDirectory(dir);
    if (await markdown.exists()) {
      final notes = <({int position, MarkdownDocument note})>[];
      await for (final file in _noteFiles(markdown)) {
        final contents = await file.readAsString();
        final end = contents.indexOf('\n---\n', 4);
        if (!contents.startsWith('---\n') || end == -1) {
          throw FormatException('Metadatos inválidos en ${file.path}.');
        }
        final data = jsonDecode(contents.substring(4, end)) as Map;
        notes.add((
          position: data['position'] as int,
          note: MarkdownDocument(
            id: data['id'] as String,
            title: data['title'] as String,
            folder: data['folder'] as String?,
            content: contents.substring(end + 5),
          ),
        ));
      }
      notes.sort((a, b) => a.position.compareTo(b.position));
      if (notes.isNotEmpty) return notes.map((entry) => entry.note).toList();
      return null;
    }

    var file = File('${dir.path}/notes.json');
    if (!await file.exists()) file = File('${dir.path}/notebook.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map || json['version'] != 1 || json['notes'] is! List) {
      throw const FormatException('El archivo de notas no es válido.');
    }
    final notes = (json['notes'] as List).map((n) {
      if (n is! Map ||
          n['id'] is! String ||
          n['title'] is! String ||
          n['content'] is! String) {
        throw const FormatException('Una nota tiene un formato inválido.');
      }
      return MarkdownDocument(
        id: n['id'] as String,
        title: n['title'] as String,
        content: n['content'] as String,
        folder: n['folder'] as String?,
      );
    }).toList();
    if (notes.isEmpty ||
        notes.map((n) => n.id).toSet().length != notes.length) {
      throw const FormatException('No se pudieron leer las notas.');
    }
    await save(notes);
    return notes;
  }

  Stream<File> _noteFiles(Directory directory) => directory
      .list(followLinks: false)
      .where(
        (entry) =>
            entry is File &&
            RegExp(r'/nota-[0-9a-f]*\.md$').hasMatch(entry.path),
      )
      .cast<File>();

  @override
  Future<void> save(List<MarkdownDocument> notes) async {
    final root = await _directory();
    final target = _markdownDirectory(root);
    if (await target.exists()) {
      await _writeNotes(target, notes);
      return;
    }

    // Publish the initial set only once every note is ready.
    final staging = await root.createTemp('.folio-');
    try {
      await _writeNotes(staging, notes);
      await staging.rename(target.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _writeNotes(
    Directory directory,
    List<MarkdownDocument> notes,
  ) async {
    final paths = <String>{};
    for (final (position, note) in notes.indexed) {
      final id = utf8
          .encode(note.id)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final path = '${directory.path}/nota-$id.md';
      paths.add(path);
      final metadata = jsonEncode({
        'id': note.id,
        'title': note.title,
        'position': position,
        if (note.folder != null) 'folder': note.folder,
      });
      final contents = '---\n$metadata\n---\n${note.content}';
      final file = File(path);
      if (await file.exists() && await file.readAsString() == contents) {
        continue;
      }
      final temp = File('$path.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(path);
    }
    await for (final file in _noteFiles(directory)) {
      if (!paths.contains(file.path)) await file.delete();
    }
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
    return MarkdownDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: file.name.replaceFirst(
        RegExp(r'\.(md|markdown|txt)$', caseSensitive: false),
        '',
      ),
      content: utf8.decode(bytes),
    );
  }

  @override
  Future<bool> exportMarkdown(MarkdownDocument note) async {
    final title = note.title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    final path = await FilePicker.saveFile(
      fileName: '${title.isEmpty ? 'nota' : title}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
      bytes: Uint8List.fromList(utf8.encode(note.content)),
    );
    return path != null;
  }
}
