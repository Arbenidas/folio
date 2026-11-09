import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'dart:async';
import 'dart:typed_data';

import '../../../../core/local_markdown.dart';
import 'markdown_tasks.dart';
import 'preview_attachment.dart';

/// Conserva el Markdown construido cuando solo cambia el cursor o el guardado.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    super.key,
    required this.content,
    required this.controller,
    this.noteId,
    this.onToggleTask,
    this.readImage,
    this.compact = false,
  });

  final String content;
  final ScrollController controller;
  final String? noteId;
  final void Function(String noteId, String source, int offset)? onToggleTask;
  final Future<Uint8List?> Function(String noteId, String reference)? readImage;
  final bool compact;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  Widget? _markdown;
  Timer? _renderDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdown = null;
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
      _renderDebounce = Timer(const Duration(milliseconds: 160), () {
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
  Widget build(BuildContext context) =>
      RepaintBoundary(child: _markdown ??= _buildMarkdown(context));

  Widget _buildMarkdown(BuildContext context) {
    final source = widget.content;
    final noteId = widget.noteId;
    final theme = Theme.of(context);
    final compactStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      h2: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
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
    return Scrollbar(
      controller: widget.controller,
      child: SingleChildScrollView(
        controller: widget.controller,
        padding: widget.compact
            ? const EdgeInsets.fromLTRB(18, 15, 18, 20)
            : const EdgeInsets.fromLTRB(24, 22, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: MarkdownBody(
              data: source,
              fitContent: !widget.compact,
              selectable: true,
              paddingBuilders: {'li': tasks},
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
                  : MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        height: 1.75,
                      ),
                      h1: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 30,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                      h2: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 24,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                      h3: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 20,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                      h4: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 17,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                      h5: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                      h6: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                      code: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      blockquote: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        height: 1.65,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
