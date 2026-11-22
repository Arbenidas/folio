import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/local_markdown.dart';
import 'markdown_tasks.dart';
import 'preview_attachment.dart';
import 'preview_code_block.dart';

/// Conserva el Markdown construido cuando solo cambia el cursor o el guardado.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    super.key,
    required this.content,
    required this.controller,
    this.noteId,
    this.onToggleTask,
    this.onTapLink,
    this.readImage,
    this.compact = false,
    this.header,
  });

  final String content;
  final ScrollController controller;
  final String? noteId;
  final void Function(String noteId, String source, int offset)? onToggleTask;
  final Future<Uint8List?> Function(String noteId, String reference)? readImage;
  final void Function(String noteId, String href)? onTapLink;
  final bool compact;
  final Widget? header;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  Widget? _markdown;
  Timer? _renderDebounce;
  ThemeData? _lastTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    if (_lastTheme != theme) {
      _lastTheme = theme;
      _markdown = null;
    }
  }

  @override
  void didUpdateWidget(MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId ||
        oldWidget.compact != widget.compact) {
      _renderDebounce?.cancel();
      _markdown = null;
    } else if (oldWidget.content != widget.content ||
        oldWidget.controller != widget.controller) {
      _renderDebounce?.cancel();
      _renderDebounce = Timer(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _markdown = null);
      });
    }
  }

  @override
  void dispose() {
    _renderDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markdown = _markdown ??= _buildMarkdown(context);
    final header = widget.header;
    return RepaintBoundary(
      child: Scrollbar(
        controller: widget.controller,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: widget.controller,
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(18, 15, 18, 20)
                : const EdgeInsets.fromLTRB(32, 26, 32, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: header == null
                    ? markdown
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [header, markdown],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdown(BuildContext context) {
    final source = widget.content;
    final noteId = widget.noteId;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      a: TextStyle(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary.withValues(alpha: 0.45),
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant, width: 1.2),
        ),
      ),
    );
    final compactStyle = baseStyle.copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
      h2: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.32,
      ),
      h3: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      blockSpacing: 8,
      listIndent: 16,
    );
    final tasks = MarkdownTasks(
      source,
      noteId == null
          ? null
          : (offset) {
              widget.onToggleTask?.call(noteId, source, offset);
            },
    );
    return MarkdownBody(
      data: source,
      fitContent: !widget.compact,
      selectable: true,
      paddingBuilders: {'li': tasks},
      builders: {'pre': PreviewCodeBlock()},
      onTapLink: widget.onTapLink == null
          ? null
          : (_, href, _) {
              if (noteId != null && href != null) {
                widget.onTapLink?.call(noteId, href);
              }
            },
      checkboxBuilder: tasks.checkbox,
      sizedImageBuilder: (config) {
        final load = widget.readImage;
        final uri = config.uri;
        if (noteId == null ||
            load == null ||
            uri.hasScheme ||
            uri.hasAuthority ||
            !uri.path.startsWith('.folio-assets/')) {
          return localMarkdownImage(config);
        }
        return PreviewAttachment(
          readImage: load,
          noteId: noteId,
          reference: uri.toString(),
          alt: config.alt,
          placeholder: localMarkdownImage(config),
        );
      },
      styleSheet: widget.compact
          ? compactStyle
          : baseStyle.copyWith(
              blockSpacing: 14,
              h1Padding: const EdgeInsets.only(top: 12, bottom: 4),
              h2Padding: const EdgeInsets.only(top: 10, bottom: 2),
              h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
              p: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                height: 1.8,
                color: colors.onSurface,
              ),
              h1: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 30,
                height: 1.28,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              h2: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 23,
                height: 1.35,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              h3: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 19,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              h4: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 17,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              h5: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              h6: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
              code: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12.5,
                color: colors.onSurface,
                backgroundColor: colors.surfaceContainerHigh,
              ),
              blockquote: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15.5,
                height: 1.72,
                color: colors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              blockquoteDecoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  left: BorderSide(
                    color: colors.primary.withValues(alpha: 0.78),
                    width: 3.5,
                  ),
                ),
              ),
            ),
    );
  }
}
