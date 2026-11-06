import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_repository.dart';
import '../../domain/document_repository.dart';
import '../../domain/markdown_document.dart';
import '../../../../core/first_run_config.dart';

final editorProvider = Provider<EditorNotifier>((ref) {
  final editor = EditorNotifier(
    FileRepository(directory: NotesStorage.directory),
  );
  ref.onDispose(editor.dispose);
  editor.load();
  return editor;
});

/// Estado compartido de las notas. El estado del teclado vive en su widget.
class EditorNotifier extends ChangeNotifier {
  EditorNotifier(this.repository);
  DocumentRepository repository;
  List<MarkdownDocument> notes = [];
  String? selectedId;
  bool loading = true;
  bool loadFailed = false;
  bool importing = false;
  String? error;
  String saveStatus = 'Cargando…';
  final contentListenable = ValueNotifier<String>('');
  final saveStatusListenable = ValueNotifier<String>('Cargando…');
  Timer? _timer;
  Future<void> _writes = Future.value();
  int _revision = 0;
  bool _disposed = false;
  MarkdownDocument get note => notes.firstWhere((n) => n.id == selectedId);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    loadFailed = false;
    error = null;
    _emit();
    try {
      notes = await repository.load().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            'La lectura de las notas tardó demasiado. Comprueba que la carpeta de notas esté disponible.',
          );
        },
      );
      selectedId = notes.first.id;
      contentListenable.value = note.content;
      _setSaveStatus('Guardado');
    } catch (e) {
      loadFailed = true;
      error =
          'No se pudieron abrir las notas. El archivo original se conserva. $e';
    } finally {
      loading = false;
      _emit();
    }
  }

  void clearError() {
    error = null;
    _emit();
  }

  void select(String id) {
    selectedId = id;
    contentListenable.value = note.content;
    _emit();
  }

  void create({String title = 'Nueva nota', String? folder}) {
    final note = MarkdownDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: '',
      folder: folder,
    );
    notes = [...notes, note];
    selectedId = note.id;
    _changed();
  }

  void deleteNote(String id) {
    final index = notes.indexWhere((note) => note.id == id);
    if (index < 0) return;

    final wasSelected = selectedId == id;
    notes = [...notes]..removeAt(index);
    if (notes.isEmpty) {
      final replacement = MarkdownDocument(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'Nueva nota',
        content: '',
      );
      notes = [replacement];
      selectedId = replacement.id;
    } else if (wasSelected) {
      selectedId = notes[index.clamp(0, notes.length - 1)].id;
    }
    _changed();
  }

  /// Quita la carpeta y conserva sus notas y subcarpetas, reubicándolas
  /// en la carpeta padre. Las notas no se eliminan con esta acción.
  void deleteFolder(String folder) {
    final parent = folder.contains('/')
        ? folder.substring(0, folder.lastIndexOf('/'))
        : null;
    final prefix = '$folder/';
    var changed = false;
    notes = notes.map((note) {
      final path = note.folder;
      if (path == folder) {
        changed = true;
        return note.copyWith(folder: parent, clearFolder: parent == null);
      }
      if (path?.startsWith(prefix) == true) {
        final rebased = path!.substring(prefix.length);
        changed = true;
        return note.copyWith(
          folder: parent == null ? rebased : '$parent/$rebased',
        );
      }
      return note;
    }).toList();
    if (changed) _changed();
  }

  void update({String? title, String? content}) {
    final index = notes.indexWhere((note) => note.id == selectedId);
    if (index < 0 || (title == null && content == null)) return;
    notes = [...notes]
      ..[index] = notes[index].copyWith(title: title, content: content);
    if (content != null) contentListenable.value = content;
    // While typing, notify only the preview and save label. The outer editor
    // tree and sidebar do not need to rebuild for each character.
    _changed(notify: title != null);
  }

  void moveToFolder(String noteId, String folder) {
    final current = notes.where((note) => note.id == noteId);
    if (current.isEmpty || current.first.folder == folder) return;
    notes = notes
        .map((note) => note.id == noteId ? note.copyWith(folder: folder) : note)
        .toList();
    _changed();
  }

  void moveFolderTo(String folder, String destination) {
    if (folder == destination || destination.startsWith('$folder/')) return;
    final newPath = '$destination/${folder.split('/').last}';
    notes = notes.map((note) {
      final path = note.folder;
      if (path == folder || path?.startsWith('$folder/') == true) {
        return note.copyWith(
          folder: '$newPath${path!.substring(folder.length)}',
        );
      }
      return note;
    }).toList();
    _changed();
  }

  void _changed({bool notify = true}) {
    _revision++;
    _setSaveStatus('Guardando…');
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () => unawaited(save()));
    if (notify) _emit();
  }

  void _setSaveStatus(String value) {
    saveStatus = value;
    saveStatusListenable.value = value;
  }

  Future<void> save() {
    _timer?.cancel();
    if (loading || loadFailed) return Future.value();
    final snapshot = List<MarkdownDocument>.of(notes);
    final revision = _revision;
    _writes = _writes.then((_) async {
      try {
        await repository.save(snapshot);
        if (revision == _revision) _setSaveStatus('Guardado');
      } catch (e) {
        _setSaveStatus('Error al guardar');
        error = 'No se pudieron guardar los cambios: $e';
        _emit();
      }
    });
    return _writes;
  }

  Future<void> changeStorageDirectory(
    Directory destination, {
    Future<void> Function()? beforeSwitch,
  }) async {
    String normalize(String path) => path.replaceAll(RegExp(r'/+$'), '');
    final currentDirectory = NotesStorage.directory;
    if (currentDirectory != null &&
        normalize(currentDirectory.path) == normalize(destination.path)) {
      return;
    }

    await save();
    final copied = await FileRepository.copyNotesInto(
      destination,
      List<MarkdownDocument>.of(notes),
    );
    await beforeSwitch?.call();
    if (_disposed) return;

    repository = FileRepository(directory: destination);
    NotesStorage.directory = destination;
    notes = copied;
    selectedId = copied.any((item) => item.id == selectedId)
        ? selectedId
        : copied.first.id;
    contentListenable.value = note.content;
    _setSaveStatus('Guardado');
    error = null;
    _revision++;
    _emit();
  }

  Future<void> importMarkdown() async {
    if (importing) return;
    importing = true;
    _emit();
    try {
      final note = await repository.importMarkdown();
      if (note != null && !_disposed) {
        notes = [...notes, note];
        selectedId = note.id;
        _changed();
      }
    } catch (e) {
      error = 'No se pudo abrir el archivo: $e';
    } finally {
      importing = false;
      _emit();
    }
  }

  Future<bool> exportMarkdown() async {
    final snapshot = note;
    try {
      return await repository.exportMarkdown(snapshot);
    } catch (e) {
      error = 'No se pudo exportar la nota: $e';
      _emit();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    contentListenable.dispose();
    saveStatusListenable.dispose();
    super.dispose();
  }
}
