import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../domain/markdown_document.dart';
import 'editor_motion.dart';
import 'note_link_suggestions.dart';

class OutlineHeading {
  const OutlineHeading({
    required this.level,
    required this.title,
    required this.offset,
  });

  final int level;
  final String title;
  final int offset;
}

class BacklinkEntry {
  const BacklinkEntry({required this.note, required this.excerpt});

  final MarkdownDocument note;
  final String excerpt;
}

abstract final class NoteMetadataExtractor {
  static final _heading = RegExp(r'^ {0,3}(#{1,4})[ \t]+(.+?)[ \t]*#*$');
  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
  static final _tag = RegExp(
    r'(?:^|(?<=\s))(#[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ][\wáéíóúÁÉÍÓÚñÑüÜ-]{0,31})',
  );
  static final _mdLink = RegExp(r'\[[^\]]+\]\(<?([^>\)\s]+)>?\)');
  static final _wikiLink = RegExp(r'\[\[([^\[\]\n]+)\]\]');

  static List<OutlineHeading> extractHeadings(String markdown) {
    final headings = <OutlineHeading>[];
    String? fence;
    var offset = 0;
    for (final line in markdown.split('\n')) {
      final f = _fence.firstMatch(line);
      if (fence != null) {
        if (f != null && f.group(1)!.startsWith(fence)) fence = null;
      } else if (f != null) {
        fence = f.group(1)![0];
      } else if (_heading.firstMatch(line) case final m?) {
        headings.add(
          OutlineHeading(
            level: m.group(1)!.length,
            title: m.group(2)!.trim(),
            offset: offset,
          ),
        );
      }
      offset += line.length + 1;
    }
    return headings;
  }

  static List<String> extractTags(String markdown) {
    final tags = <String>{};
    String? fence;
    for (final line in markdown.split('\n')) {
      final f = _fence.firstMatch(line);
      if (fence != null) {
        if (f != null && f.group(1)!.startsWith(fence)) fence = null;
        continue;
      }
      if (f != null) {
        fence = f.group(1)![0];
        continue;
      }
      if (_heading.hasMatch(line)) continue;
      for (final m in _tag.allMatches(line)) {
        tags.add(m.group(1)!.toLowerCase());
      }
    }
    return tags.toList()..sort();
  }

  static List<String> extractAllNotebookTags(List<MarkdownDocument> notes) {
    final counts = <String, int>{};
    for (final note in notes) {
      for (final tag in extractTags(note.content)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted;
  }

  static List<BacklinkEntry> findBacklinks(
    MarkdownDocument target,
    List<MarkdownDocument> notes,
  ) {
    final results = <BacklinkEntry>[];
    final targetTitleLower = target.title.toLowerCase();
    for (final note in notes) {
      if (note.id == target.id) continue;
      String? matchedLine;
      for (final line in note.content.split('\n')) {
        var hits = false;
        for (final m in _mdLink.allMatches(line)) {
          final resolved = NoteLinkQuery.targetId(note.id, m.group(1)!);
          if (resolved == target.id) {
            hits = true;
            break;
          }
        }
        if (!hits) {
          for (final m in _wikiLink.allMatches(line)) {
            if (m.group(1)!.trim().toLowerCase() == targetTitleLower) {
              hits = true;
              break;
            }
          }
        }
        if (hits) {
          matchedLine = line.replaceAll(RegExp(r'[#*_>`]'), '').trim();
          break;
        }
      }
      if (matchedLine != null) {
        results.add(BacklinkEntry(note: note, excerpt: matchedLine));
      }
    }
    return results;
  }
}

class NoteInspectorPanel extends StatelessWidget {
  const NoteInspectorPanel({
    super.key,
    required this.note,
    required this.content,
    required this.allNotes,
    required this.onJumpToOffset,
    required this.onOpenNote,
    required this.onSearchTag,
    required this.onClose,
  });

  final MarkdownDocument? note;
  final String content;
  final List<MarkdownDocument> allNotes;
  final ValueChanged<int> onJumpToOffset;
  final ValueChanged<MarkdownDocument> onOpenNote;
  final ValueChanged<String> onSearchTag;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final activeNote = note;
    final headings = NoteMetadataExtractor.extractHeadings(content);
    final noteTags = NoteMetadataExtractor.extractTags(content);
    final allTags = NoteMetadataExtractor.extractAllNotebookTags(allNotes);
    final backlinks = activeNote == null
        ? const <BacklinkEntry>[]
        : NoteMetadataExtractor.findBacklinks(activeNote, allNotes);

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            decoration: BoxDecoration(
              color: style.isGraphic ? colors.surfaceContainer : null,
              border: Border(
                bottom: BorderSide(
                  color: style.isGraphic ? style.ink : colors.outlineVariant,
                  width: style.isGraphic ? style.lineWidth : 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.list_bullet_indent,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  'ÍNDICE Y ENLACES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: style.isRetro ? 'Menlo' : null,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Cerrar índice (⌘⇧O)',
                  child: AppIconButton(
                    semanticLabel: 'Cerrar índice',
                    icon: CupertinoIcons.xmark,
                    size: 15,
                    padding: const EdgeInsets.all(5),
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _sectionTitle('ÍNDICE', headings.length, colors),
                const SizedBox(height: 8),
                if (headings.isEmpty)
                  _emptyHint(
                    'Añade títulos con # o ## para navegar rápido por esta nota.',
                    colors,
                  )
                else
                  for (final heading in headings)
                    _OutlineRow(
                      heading: heading,
                      onTap: () => onJumpToOffset(heading.offset),
                    ),
                const SizedBox(height: 20),
                _sectionTitle('ETIQUETAS EN ESTA NOTA', noteTags.length, colors),
                const SizedBox(height: 8),
                if (noteTags.isEmpty)
                  _emptyHint(
                    'Escribe #etiqueta en tu nota para clasificarla.',
                    colors,
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in noteTags)
                        _TagPill(tag: tag, onTap: () => onSearchTag(tag)),
                    ],
                  ),
                if (allTags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle(
                    'TODAS LAS ETIQUETAS',
                    allTags.length,
                    colors,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in allTags.take(18))
                        _TagPill(
                          tag: tag,
                          muted: !noteTags.contains(tag),
                          onTap: () => onSearchTag(tag),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                _sectionTitle('ENLACES ENTRANTES', backlinks.length, colors),
                const SizedBox(height: 8),
                if (backlinks.isEmpty)
                  _emptyHint(
                    'Otras notas que enlacen aquí con [[${activeNote?.title ?? 'Nota'}]] aparecerán en esta sección.',
                    colors,
                  )
                else
                  for (final entry in backlinks)
                    _BacklinkCard(
                      entry: entry,
                      onTap: () => onOpenNote(entry.note),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count, ColorScheme colors) => Row(
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );

  Widget _emptyHint(String text, ColorScheme colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: colors.surface.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.65)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: colors.onSurfaceVariant.withValues(alpha: 0.85),
      ),
    ),
  );
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({required this.heading, required this.onTap});

  final OutlineHeading heading;
  final VoidCallback onTap;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final indent = (widget.heading.level - 1) * 12.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 120),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.fromLTRB(8 + indent, 6, 8, 6),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.secondaryContainer.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.heading.level == 1
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.heading.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.heading.level == 1 ? 12.5 : 12,
                    fontWeight: widget.heading.level <= 2
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: _hovered
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
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

class _TagPill extends StatefulWidget {
  const _TagPill({
    required this.tag,
    required this.onTap,
    this.muted = false,
  });

  final String tag;
  final VoidCallback onTap;
  final bool muted;

  @override
  State<_TagPill> createState() => _TagPillState();
}

class _TagPillState extends State<_TagPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.tertiaryContainer
                : widget.muted
                ? colors.surfaceContainerLowest
                : colors.tertiaryContainer.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.muted
                  ? colors.outlineVariant
                  : colors.tertiary.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            widget.tag,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: widget.muted && !_hovered
                  ? colors.onSurfaceVariant
                  : colors.onTertiaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _BacklinkCard extends StatefulWidget {
  const _BacklinkCard({required this.entry, required this.onTap});

  final BacklinkEntry entry;
  final VoidCallback onTap;

  @override
  State<_BacklinkCard> createState() => _BacklinkCardState();
}

class _BacklinkCardState extends State<_BacklinkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 130),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.secondaryContainer.withValues(alpha: 0.7)
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _hovered
                  ? colors.primary.withValues(alpha: 0.5)
                  : colors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.doc_text,
                    size: 13,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.entry.note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.entry.excerpt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.entry.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
