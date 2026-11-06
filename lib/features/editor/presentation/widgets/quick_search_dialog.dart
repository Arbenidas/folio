import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';
import '../../domain/markdown_document.dart';

class QuickSearchHit {
  QuickSearchHit.note(MarkdownDocument note)
    : folderPath = null,
      title = note.title,
      subtitle = '',
      document = note;

  const QuickSearchHit.folder(this.folderPath, this.title, this.subtitle)
    : document = null;

  final MarkdownDocument? document;
  final String? folderPath;
  final String title;
  final String subtitle;

  bool get isFolder => folderPath != null;
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
      for (final note in widget.notes) QuickSearchHit.note(note),
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
    return '${note.title} ${note.folder ?? ''} ${note.content}';
  }

  List<QuickSearchHit> get _matches {
    final query = _query.trim().toLowerCase();
    final hits = _allHits.where((hit) {
      return query.isEmpty ||
          _searchableText(hit).toLowerCase().contains(query);
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
  Widget build(BuildContext context) => MacosSheet(
    insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
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
                  const Expanded(
                    child: Text(
                      'Buscar en Folio',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
              MacosSearchField<QuickSearchHit>(
                controller: _controller,
                autofocus: true,
                placeholder: 'Busca notas, carpetas o contenido…',
                results: null,
                onChanged: (query) => setState(() {
                  _query = query;
                  _selectedIndex = 0;
                }),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 330),
                child: _matches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(22),
                        child: Text('No se encontraron notas ni carpetas.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _visibleHits.length,
                        itemBuilder: (context, index) {
                          final hit = _visibleHits[index];
                          final selected = index == _selectedIndex;
                          final note = hit.document;
                          final subtitle = hit.isFolder
                              ? hit.subtitle
                              : [
                                  if (note!.folder != null) note.folder!,
                                  _noteExcerpt(note),
                                ].join('  ·  ');
                          return MouseRegion(
                            onEnter: (_) =>
                                setState(() => _selectedIndex = index),
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: () => _select(hit),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 110),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? MacosTheme.of(
                                          context,
                                        ).primaryColor.withValues(alpha: 0.12)
                                      : const Color(0x00000000),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    MacosIcon(
                                      hit.isFolder
                                          ? CupertinoIcons.folder
                                          : CupertinoIcons.doc_text,
                                      size: 17,
                                      color: MacosTheme.of(
                                        context,
                                      ).primaryColor,
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
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: MacosColors
                                                  .secondaryLabelColor
                                                  .resolveFrom(context),
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
              const SizedBox(height: 8),
              Text(
                _matches.length > _visibleHits.length
                    ? '↑ ↓ para moverte     ↵ para abrir     Esc para cerrar · escribe más para afinar'
                    : '↑ ↓ para moverte     ↵ para abrir     Esc para cerrar',
                style: TextStyle(
                  fontSize: 10,
                  color: MacosColors.secondaryLabelColor.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
