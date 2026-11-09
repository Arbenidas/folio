import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Dialog, Theme;
import 'package:flutter/services.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/theme.dart';
import '../../domain/markdown_document.dart';
import 'editor_motion.dart';

class QuickSearchHit {
  QuickSearchHit.note(MarkdownDocument note, this.contentQuery)
    : folderPath = null,
      title = note.title,
      subtitle = '',
      document = note;

  const QuickSearchHit.folder(this.folderPath, this.title, this.subtitle)
    : document = null,
      contentQuery = null;

  final MarkdownDocument? document;
  final String? folderPath;
  final String title;
  final String subtitle;
  final String? contentQuery;

  bool get isFolder => folderPath != null;

  static Match? findContent(String content, String query) => query.isEmpty
      ? null
      : RegExp(
          RegExp.escape(query),
          caseSensitive: false,
          unicode: true,
        ).firstMatch(content);
}

class QuickSearchDialog extends StatefulWidget {
  const QuickSearchDialog({super.key, required this.notes});

  final List<MarkdownDocument> notes;

  @override
  State<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<QuickSearchDialog> {
  final _controller = TextEditingController();
  String _query = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncQuery);
  }

  void _syncQuery() {
    if (!mounted || _query == _controller.text) return;
    setState(() {
      _query = _controller.text;
      _selectedIndex = 0;
    });
  }

  List<QuickSearchHit> get _allHits {
    final folders = <String>{};
    for (final note in widget.notes) {
      final path = note.folder;
      if (path == null) continue;
      final segments = path.split('/');
      for (var i = 0; i < segments.length; i++) {
        folders.add(segments.take(i + 1).join('/'));
      }
    }

    return [
      for (final note in widget.notes) QuickSearchHit.note(note, _query.trim()),
      for (final path in folders)
        QuickSearchHit.folder(
          path,
          path.split('/').last,
          path.replaceAll('/', '  ›  '),
        ),
    ];
  }

  String _searchableText(QuickSearchHit hit) {
    if (hit.isFolder) return '${hit.title} ${hit.folderPath}';
    final note = hit.document!;
    return '${note.title} ${note.folder ?? ''}';
  }

  List<QuickSearchHit> get _matches {
    final query = _query.trim().toLowerCase();
    final hits = _allHits.where((hit) {
      return query.isEmpty ||
          _searchableText(hit).toLowerCase().contains(query) ||
          (hit.document != null &&
              QuickSearchHit.findContent(
                    hit.document!.content,
                    hit.contentQuery!,
                  ) !=
                  null);
    }).toList();
    if (query.isNotEmpty) {
      int score(QuickSearchHit hit) {
        final title = hit.title.toLowerCase();
        if (title.startsWith(query)) return 0;
        if (title.contains(query)) return 1;
        if ((hit.folderPath ?? hit.document?.folder ?? '')
            .toLowerCase()
            .contains(query)) {
          return 2;
        }
        return 3;
      }

      hits.sort((a, b) => score(a).compareTo(score(b)));
    }
    return hits;
  }

  List<QuickSearchHit> get _visibleHits => _matches.take(7).toList();

  String _noteExcerpt(MarkdownDocument note) {
    final lines = note.content
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[#>*_`~]'), '').trim())
        .where((line) => line.isNotEmpty);
    return lines.isEmpty ? 'Nota vacía' : lines.first;
  }

  TextSpan _excerpt(QuickSearchHit hit, Color highlight) {
    final note = hit.document;
    if (note == null) return TextSpan(text: hit.subtitle);
    final path = note.folder == null ? '' : '${note.folder}  ·  ';
    final match = QuickSearchHit.findContent(note.content, hit.contentQuery!);
    if (match == null) return TextSpan(text: '$path${_noteExcerpt(note)}');
    final before = note.content.substring(0, match.start).characters;
    final after = note.content.substring(match.end).characters;
    String oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
    return TextSpan(
      children: [
        TextSpan(
          text:
              '${before.length > 24 ? '…' : path}${oneLine(before.takeLast(24).toString())}',
        ),
        TextSpan(
          text: oneLine(match.group(0)!),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            backgroundColor: highlight,
          ),
        ),
        TextSpan(
          text:
              '${oneLine(after.take(48).toString())}${after.length > 48 ? '…' : ''}',
        ),
      ],
    );
  }

  void _select(QuickSearchHit hit) => Navigator.of(context).pop(hit);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_visibleHits.isEmpty) return KeyEventResult.handled;
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _visibleHits.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_visibleHits.isEmpty) return KeyEventResult.handled;
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _visibleHits.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _visibleHits.isNotEmpty) {
      _select(_visibleHits[_selectedIndex.clamp(0, _visibleHits.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.removeListener(_syncQuery);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final matches = _matches;
    final visibleHits = matches.take(7).toList();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 76, 24, 24),
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: style.isGraphic
          ? style.outline
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Focus(
            onKeyEvent: _handleKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Buscar en Folio',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    AppIconButton(
                      semanticLabel: 'Cerrar búsqueda',
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CupertinoSearchTextField(
                  controller: _controller,
                  autofocus: true,
                  placeholder: 'Busca notas, carpetas o contenido…',
                  style: TextStyle(fontSize: 14, color: colors.onSurface),
                  placeholderStyle: TextStyle(
                    fontSize: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  itemColor: colors.onSurfaceVariant,
                  itemSize: 16,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outline),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 330),
                    child: matches.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(22),
                            child: Text(
                              'No se encontraron notas ni carpetas.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visibleHits.length,
                            itemBuilder: (context, index) {
                              final hit = visibleHits[index];
                              final selected = index == _selectedIndex;
                              final foreground = selected
                                  ? colors.onSecondaryContainer
                                  : colors.onSurface;
                              return MouseRegion(
                                onEnter: (_) =>
                                    setState(() => _selectedIndex = index),
                                child: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  onPressed: () => _select(hit),
                                  child: AnimatedContainer(
                                    duration: EditorMotion.duration(
                                      context,
                                      110,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? colors.secondaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hit.isFolder
                                              ? CupertinoIcons.folder
                                              : CupertinoIcons.doc_text,
                                          size: 17,
                                          color: foreground,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                hit.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: foreground,
                                                ),
                                              ),
                                              Text.rich(
                                                _excerpt(
                                                  hit,
                                                  colors.primary.withValues(
                                                    alpha: 0.18,
                                                  ),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: selected
                                                      ? foreground
                                                      : colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  matches.length > visibleHits.length
                      ? '↑ ↓ para moverte     ↵ para abrir     Esc para cerrar · escribe más para afinar'
                      : '↑ ↓ para moverte     ↵ para abrir     Esc para cerrar',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
