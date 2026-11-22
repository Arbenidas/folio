import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/markdown_document.dart';

class NoteLinkQuery {
  const NoteLinkQuery(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  static final _opening = RegExp(r'(?:^|[^\\\[])(\[\[([^\[\]\r\n]*))$');
  static final _closing = RegExp(r'^[^\[\]\r\n]*\]\]');

  static NoteLinkQuery? at(TextEditingValue value) {
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return null;
    }
    final caret = value.selection.extentOffset;
    if (caret < 2 || caret > value.text.length) return null;
    final lineStart = value.text.lastIndexOf('\n', caret - 1) + 1;
    final match = _opening.firstMatch(value.text.substring(lineStart, caret));
    if (match == null) return null;
    final query = match.group(2)!;
    final closing = _closing.matchAsPrefix(value.text, caret);
    return NoteLinkQuery(
      caret - query.length - 2,
      closing?.end ?? caret,
      query,
    );
  }

  List<MarkdownDocument> suggestions(
    List<MarkdownDocument> notes,
    String? sourceId,
  ) {
    final query = text.trim().toLowerCase();
    final prefix = <MarkdownDocument>[];
    final other = <MarkdownDocument>[];
    for (final note in notes) {
      if (note.id == sourceId) continue;
      final title = note.title.toLowerCase();
      if (title.startsWith(query)) {
        prefix.add(note);
        if (prefix.length == 6) return prefix;
      } else if (other.length < 6 &&
          (title.contains(query) || note.id.toLowerCase().contains(query))) {
        other.add(note);
      }
    }
    return [...prefix, ...other.take(6 - prefix.length)];
  }

  static String markdownLink(String sourceId, MarkdownDocument target) {
    final relative = p.posix.relative(
      target.id,
      from: p.posix.dirname(sourceId),
    );
    final url = Uri(pathSegments: relative.split('/')).toString();
    final label = target.title.replaceAllMapped(
      RegExp(r'[\\\[\]`*_~]'),
      (match) => '\\${match[0]}',
    );
    return '[$label](<$url>)';
  }

  static String? targetId(String sourceId, String href) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.path.isEmpty ||
        uri.path.startsWith('/') ||
        uri.hasQuery) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.any(
      (segment) => segment.contains('/') || segment.contains('\\'),
    )) {
      return null;
    }
    return p.posix.normalize(
      p.posix.join(p.posix.dirname(sourceId), segments.join('/')),
    );
  }
}

class NoteLinkSuggestions extends StatelessWidget {
  const NoteLinkSuggestions({
    super.key,
    required this.notes,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<MarkdownDocument> notes;
  final int selectedIndex;
  final ValueChanged<MarkdownDocument> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = notes[selectedIndex];
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
                      child: Text(
                        'Enlazar nota · ↑ ↓ · ↵',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final (index, note) in notes.indexed)
                      Ink(
                        color: index == selectedIndex
                            ? colors.secondaryContainer
                            : null,
                        child: InkWell(
                          canRequestFocus: false,
                          onTap: () => onSelect(note),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Text(
                              note.folder == null
                                  ? note.title
                                  : '${note.title} · ${note.folder}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: index == selectedIndex
                                    ? colors.onSecondaryContainer
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (constraints.maxWidth >= 360)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          selected.content.isEmpty
                              ? 'Nota vacía'
                              : selected.content.trimLeft(),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
