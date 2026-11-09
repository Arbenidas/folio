import 'dart:typed_data';

import 'notebook_snapshot.dart';
import 'markdown_document.dart';
import 'trashed_note.dart';

abstract interface class DocumentRepository {
  Future<NotebookSnapshot> load();
  Future<NotebookSnapshot> scan();
  Stream<void> watch();
  Future<MarkdownDocument> createNote({
    String title = 'Nueva nota',
    String? folder,
    String content = '',
  });
  Future<MarkdownDocument> saveNote(MarkdownDocument note);
  Future<MarkdownDocument> renameNote(String id, String title);
  Future<MarkdownDocument> moveNote(String id, String? folder);
  Future<void> deleteNote(String id);
  Future<List<TrashedNote>> listTrash();
  Future<MarkdownDocument> restoreDeletedNote(String trashId);
  Future<String> saveImage(String noteId, Uint8List png);
  Future<Uint8List?> readImage(String noteId, String reference);
  Future<String> createFolder(String path);
  Future<String> renameFolder(String path, String title);
  Future<String> moveFolder(String path, String? destination);
  Future<void> deleteFolder(String path);
  Future<MarkdownDocument?> importMarkdown();
  Future<bool> exportMarkdown(MarkdownDocument note);
}
