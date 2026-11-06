/// Una nota no depende de Flutter, del disco ni de cómo se muestra.
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

  /// Ruta de la carpeta; por ejemplo, `Flutter/HTTP` para una subcarpeta.
  final String? folder;

  MarkdownDocument copyWith({
    String? title,
    String? content,
    String? folder,
    bool clearFolder = false,
  }) => MarkdownDocument(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    folder: clearFolder ? null : folder ?? this.folder,
  );
}
