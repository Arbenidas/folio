import 'markdown_document.dart';

/// A point-in-time view of Markdown notes and all folders in a notebook.
class NotebookSnapshot {
  NotebookSnapshot({
    required List<MarkdownDocument> notes,
    required Set<String> folderPaths,
    List<NotebookReadError> readErrors = const [],
  }) : notes = List.unmodifiable(notes),
       folderPaths = Set.unmodifiable(folderPaths),
       readErrors = List.unmodifiable(readErrors);

  final List<MarkdownDocument> notes;

  /// Relative paths for all folders, including folders with no notes.
  final Set<String> folderPaths;
  final List<NotebookReadError> readErrors;
}

class NotebookReadError {
  const NotebookReadError(this.relativePath, this.message);

  final String relativePath;
  final String message;
}
