import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../domain/note_template.dart';
import 'editor_motion.dart';
import 'markdown_preview.dart';

class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key});

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  final _scroll = ScrollController(keepScrollOffset: false);
  NoteTemplate _selected = NoteTemplate.daily;
  TemplateCategory? _categoryFilter;
  bool _showBlankStructure = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<NoteTemplate> get _visibleTemplates => _categoryFilter == null
      ? NoteTemplate.values
      : NoteTemplate.values
            .where((item) => item.category == _categoryFilter)
            .toList();

  void _selectCategory(TemplateCategory? category) {
    setState(() {
      _categoryFilter = category;
      final list = _visibleTemplates;
      if (!list.contains(_selected) && list.isNotEmpty) {
        _selected = list.first;
      }
    });
  }

  IconData _iconFor(NoteTemplate option) => switch (option) {
    NoteTemplate.daily => CupertinoIcons.sun_max,
    NoteTemplate.weekly => CupertinoIcons.calendar,
    NoteTemplate.goals => CupertinoIcons.flag,
    NoteTemplate.project => CupertinoIcons.folder_badge_person_crop,
    NoteTemplate.meeting => CupertinoIcons.person_2,
    NoteTemplate.requirements => CupertinoIcons.doc_checkmark,
    NoteTemplate.study => CupertinoIcons.book,
    NoteTemplate.idea => CupertinoIcons.lightbulb,
    NoteTemplate.article => CupertinoIcons.film,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = FolioStyle.of(context);
    final paper = colors.surfaceContainerLowest;
    final templates = _visibleTemplates;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      shape: style.isGraphic
          ? style.outline
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.outlineVariant),
            ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 860,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 16, 14, 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.doc_on_doc_fill,
                      size: 17,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plantillas',
                          style: TextStyle(
                            fontFamily: style.isRetro ? 'Menlo' : null,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Empieza con una estructura lista para tu día, proyectos o ideas.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppIconButton(
                    semanticLabel: 'Cerrar plantillas',
                    icon: CupertinoIcons.xmark,
                    size: 16,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterPill('Todas', null, colors),
                    const SizedBox(width: 6),
                    for (final category in TemplateCategory.values) ...[
                      _filterPill(category.label, category, colors),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 248,
                      child: ListView(
                        primary: false,
                        padding: const EdgeInsets.only(right: 6, bottom: 4),
                        children: [
                          for (final option in templates)
                            _TemplateOption(
                              option: option,
                              icon: _iconFor(option),
                              selected: option == _selected,
                              onTap: () => setState(() => _selected = option),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: style.isGraphic
                            ? style.panel(paper, lift: style.isPop ? 3 : 0)
                            : BoxDecoration(
                                color: paper,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 40,
                              color: style.isPop
                                  ? style.folderAccent(_selected.index)
                                  : colors.surfaceContainerLow,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _iconFor(_selected),
                                    size: 14,
                                    color: style.isPop
                                        ? style.folderForeground(
                                            _selected.index,
                                          )
                                        : colors.primary,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _selected.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontFamily: style.isRetro
                                            ? 'Menlo'
                                            : null,
                                        color: style.isPop
                                            ? style.folderForeground(
                                                _selected.index,
                                              )
                                            : colors.onSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  CupertinoSlidingSegmentedControl<bool>(
                                    groupValue: _showBlankStructure,
                                    backgroundColor:
                                        colors.surfaceContainerHigh,
                                    thumbColor: colors.surfaceContainerLowest,
                                    children: const {
                                      false: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          'Ejemplo',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                      true: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          'Estructura',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    },
                                    onValueChanged: (value) {
                                      if (value != null) {
                                        setState(
                                          () => _showBlankStructure = value,
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: style.isGraphic ? style.lineWidth : 1,
                            ),
                            Expanded(
                              child: MarkdownPreview(
                                key: ValueKey((
                                  _selected,
                                  _showBlankStructure,
                                )),
                                controller: _scroll,
                                content: _showBlankStructure
                                    ? _selected.content
                                    : _selected.example,
                                compact: true,
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
            Container(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Se creará una nota nueva editable basada en «${_selected.title}».',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Usar plantilla'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(
    String label,
    TemplateCategory? category,
    ColorScheme colors,
  ) {
    final selected = _categoryFilter == category;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => _selectCategory(category),
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.45)
                : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TemplateOption extends StatefulWidget {
  const _TemplateOption({
    required this.option,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final NoteTemplate option;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TemplateOption> createState() => _TemplateOptionState();
}

class _TemplateOptionState extends State<_TemplateOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final selected = widget.selected;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Semantics(
        selected: selected,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: widget.onTap,
            child: AnimatedContainer(
              duration: EditorMotion.duration(context, 140),
              curve: EditorMotion.curve,
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
              decoration: style.isGraphic && selected
                  ? style.panel(
                      colors.secondaryContainer,
                      lift: style.isPop ? 2 : 0,
                    )
                  : BoxDecoration(
                      color: selected
                          ? colors.secondaryContainer
                          : _hovered
                          ? colors.surfaceContainerHigh.withValues(alpha: 0.72)
                          : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? colors.primary.withValues(alpha: 0.5)
                            : colors.outlineVariant.withValues(alpha: 0.75),
                        width: selected ? 1.3 : 1,
                      ),
                    ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.16)
                          : colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      size: 14.5,
                      color: selected ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.option.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                CupertinoIcons.check_mark,
                                size: 12,
                                color: colors.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.option.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: selected
                                ? foreground.withValues(alpha: 0.85)
                                : colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
