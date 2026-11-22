import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'preview_mermaid_diagram.dart';

class PreviewCodeBlock extends MarkdownElementBuilder {
  static final _options = RegExp(
    r'''(?:^|\s)(title|filename|line)=(?:"([^"]*)"|'([^']*)'|(\S+))''',
  );
  static final _codeTokens = RegExp(
    r'''(//[^\n]*|/\*[\s\S]*?\*/)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|\b(\d+(?:\.\d+)?)\b|\b(const|let|var|final|void|function|return|if|else|for|while|import|from|class|extends|async|await|true|false|null|def|self|None|True|False)\b''',
  );
  static const _highlighted = {
    'dart',
    'js',
    'javascript',
    'ts',
    'typescript',
    'jsx',
    'tsx',
    'json',
    'java',
    'kt',
    'kotlin',
    'swift',
    'py',
    'python',
    'go',
    'rust',
    'c',
    'cpp',
    'cs',
  };

  // flutter_markdown needs a child to flush its inline buffer for <pre>.
  // The block widget below replaces that child with the styled source.
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) =>
      const SizedBox.shrink();

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.firstOrNull;
    if (code is! md.Element) return null;
    final languageClass = code.attributes['class'];
    final language = languageClass?.substring('language-'.length);
    final options = {
      for (final match in _options.allMatches(
        element.attributes['data-metadata'] ?? '',
      ))
        match.group(1)!: match.group(2) ?? match.group(3) ?? match.group(4)!,
    };
    final firstLine = int.tryParse(options['line'] ?? '');
    final showNumbers =
        firstLine != null && firstLine > 0 && firstLine <= 1000000;
    final title = options['title'];
    final file = options['filename'];
    final details = [
      if (file != null && file.isNotEmpty) file,
      ?language,
    ].join(' · ');
    final colors = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontFamily: 'Menlo',
      fontSize: 12,
      height: 1.6,
      color: colors.onSurface,
    );
    final source = code.textContent.replaceFirst(RegExp(r'\n$'), '');
    if (language?.trim().toLowerCase() == 'mermaid') {
      return PreviewMermaidDiagram(source: source, title: title);
    }
    final lines = source.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((title?.isNotEmpty ?? false) || details.isNotEmpty)
          ColoredBox(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title.isNotEmpty)
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showNumbers)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    List.generate(
                      lines.length,
                      (index) => firstLine + index,
                    ).join('\n'),
                    textAlign: TextAlign.right,
                    style: textStyle.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              SelectableText.rich(
                TextSpan(
                  style: textStyle,
                  children: _highlighted.contains(language?.toLowerCase())
                      ? _highlight(source, colors)
                      : [TextSpan(text: source)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<TextSpan> _highlight(String source, ColorScheme colors) {
    final spans = <TextSpan>[];
    var start = 0;
    for (final token in _codeTokens.allMatches(source)) {
      spans.add(TextSpan(text: source.substring(start, token.start)));
      final color = switch (token) {
        _ when token.group(1) != null => colors.onSurfaceVariant,
        _ when token.group(2) != null => colors.secondary,
        _ when token.group(3) != null => colors.tertiary,
        _ => colors.primary,
      };
      spans.add(
        TextSpan(
          text: token.group(0),
          style: TextStyle(color: color),
        ),
      );
      start = token.end;
    }
    spans.add(TextSpan(text: source.substring(start)));
    return spans;
  }
}
