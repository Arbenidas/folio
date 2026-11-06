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

    final targetNotes = File('${destination.path}/notes.json');
    final targetLegacy = File('${destination.path}/notebook.json');
    if (await targetNotes.exists() || await targetLegacy.exists()) return;

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
    final targetJson = File('${destination.path}/notes.json');
    final targetLegacy = File('${destination.path}/notebook.json');
    final hasExistingNotebook =
        await targetJson.exists() || await targetLegacy.exists();
    final destinationNotes = hasExistingNotebook
        ? await target.load()
        : <MarkdownDocument>[];

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
    final dir = await _directory();
    var file = File('${dir.path}/notes.json');
    // Recupera las notas de la versión anterior. Ese archivo queda intacto.
    if (!await file.exists()) file = File('${dir.path}/notebook.json');
    if (!await file.exists()) {
      return [
        const MarkdownDocument(
          id: 'welcome',
          title: 'Mis apuntes',
          content: '# Mis apuntes\n\nUn espacio para guardar lo que voy aprendiendo.\n\n## Hoy aprendí\n\n- \n',
        ),
      ];
    }
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
    return notes;
  }

  @override
  Future<void> save(List<MarkdownDocument> notes) async {
    final path = '${(await _directory()).path}/notes.json';
    final temp = File('$path.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'notes': notes
            .map(
              (n) => {
                'id': n.id,
                'title': n.title,
                'content': n.content,
                if (n.folder != null) 'folder': n.folder,
              },
            )
            .toList(),
      }),
      flush: true,
    );
    await temp.rename(path);
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
