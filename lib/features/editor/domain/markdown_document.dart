/// A Markdown note identified by its path relative to the notebook root.
class MarkdownDocument {
  const MarkdownDocument({
    required this.id,
    required this.title,
    required this.content,
    this.folder,
  });
  final String id;
  final String title;
  final String content;

  /// Relative folder path; for example, `Flutter/HTTP`.
  final String? folder;

  MarkdownDocument copyWith({
    String? id,
    String? title,
    String? content,
    String? folder,
    bool clearFolder = false,
  }) {
    final nextTitle = title ?? this.title;
    final nextFolder = clearFolder ? null : folder ?? this.folder;
    final locationChanged = title != null || folder != null || clearFolder;
    final nextId =
        id ??
        (locationChanged
            ? '${nextFolder == null || nextFolder.isEmpty ? '' : '$nextFolder/'}$nextTitle.md'
            : this.id);
    return MarkdownDocument(
      id: nextId,
      title: nextTitle,
      content: content ?? this.content,
      folder: nextFolder,
    );
  }
}
