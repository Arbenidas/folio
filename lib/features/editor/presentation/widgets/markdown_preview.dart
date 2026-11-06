import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'dart:async';

import '../../../../core/local_markdown.dart';

/// Conserva el Markdown construido cuando solo cambia el cursor o el guardado.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    super.key,
    required this.content,
    required this.controller,
  });

  final String content;
  final ScrollController controller;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  Widget? _markdown;
  Timer? _renderDebounce;

  @override
  void didUpdateWidget(MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
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
  Widget build(BuildContext context) => RepaintBoundary(
    child: _markdown ??= Scrollbar(
      controller: widget.controller,
      child: SingleChildScrollView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: MarkdownBody(
              data: widget.content,
              selectable: true,
              sizedImageBuilder: localMarkdownImage,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
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
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
    ),
  );
}
