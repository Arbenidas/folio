import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/note_template.dart';
import 'markdown_preview.dart';

class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key});

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  final _scroll = ScrollController(keepScrollOffset: false);
  NoteTemplate _selected = NoteTemplate.study;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = FolioStyle.of(context);
    final paper = colors.surfaceContainerLowest;
    final previewDecoration = style.isGraphic
        ? style.panel(paper, lift: style.isPop ? 4 : 0)
        : BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: style.isPop
          ? colors.surfaceContainerLow
          : colors.surface,
      child: SizedBox(
        width: 740,
        height: 516,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 26, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plantillas',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: style.isRetro ? 'Menlo' : null,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Elige una estructura para tu próxima nota.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 188,
                      child: ListView(
                        primary: false,
                        padding: const EdgeInsets.only(right: 4, bottom: 4),
                        children: [
                          for (final option in NoteTemplate.values)
                            _TemplateOption(
                              option: option,
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
                        decoration: previewDecoration,
                        foregroundDecoration: BoxDecoration(
                          border: previewDecoration.border,
                          borderRadius: previewDecoration.borderRadius,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              color: style.isPop
                                  ? style.folderAccent(_selected.index)
                                  : colors.surfaceContainerLow,
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
                              child: Text(
                                'EJEMPLO · ${_selected.title}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontFamily: style.isRetro ? 'Menlo' : null,
                                  letterSpacing: 0.7,
                                  color: style.isPop
                                      ? style.folderForeground(_selected.index)
                                      : colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: style.isGraphic ? style.lineWidth : 1,
                            ),
                            Expanded(
                              child: MarkdownPreview(
                                key: ValueKey(_selected),
                                controller: _scroll,
                                content: _selected.example,
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
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'La nota nueva tendrá campos para completar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Usar plantilla'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final NoteTemplate option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = FolioStyle.of(context);
    final icon = switch (option) {
      NoteTemplate.study => CupertinoIcons.book,
      NoteTemplate.idea => CupertinoIcons.lightbulb,
      NoteTemplate.requirements => CupertinoIcons.doc_checkmark,
    };
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          shape: style.isGraphic
              ? style.outline
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            customBorder: style.isGraphic ? style.outline : null,
            borderRadius: style.isGraphic ? null : BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          option.title,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          CupertinoIcons.check_mark,
                          size: 13,
                          color: foreground,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    option.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected ? foreground : colors.onSurfaceVariant,
                      height: 1.3,
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
