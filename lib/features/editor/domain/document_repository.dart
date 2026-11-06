import 'markdown_document.dart';

abstract interface class DocumentRepository {
  Future<List<MarkdownDocument>> load();
  Future<void> save(List<MarkdownDocument> notes);
  Future<MarkdownDocument?> importMarkdown();
  Future<bool> exportMarkdown(MarkdownDocument note);
}
