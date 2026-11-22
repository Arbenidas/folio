import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import 'editor_motion.dart';
import 'markdown_editing_assistant.dart';
import 'markdown_source_controller.dart';

class EditorPane extends StatefulWidget {
  const EditorPane({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.editableKey,
    this.linkSuggestions,
    this.centered = false,
    this.onToggleOutline,
    this.outlineActive = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<EditableTextState> editableKey;
  final Widget? linkSuggestions;
  final bool centered;
  final VoidCallback? onToggleOutline;
  final bool outlineActive;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final _scrollController = ScrollController();
  late final TextSelectionGestureDetectorBuilder
  _selectionGestureDetectorBuilder;
  final Object _tapRegionGroupId = Object();

  @override
  GlobalKey<EditableTextState> get editableTextKey => widget.editableKey;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    _selectionGestureDetectorBuilder = TextSelectionGestureDetectorBuilder(
      delegate: this,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _applyFormat(VoidCallback action) {
    action();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AppAppearance.instance, widget.controller]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final appearance = AppAppearance.instance;
      final fontFamily = appearance.editorTypography.fontFamily;
      final fontSize = appearance.editorFontSize;
      final focusMode = appearance.focusMode;
      if (widget.controller case final MarkdownSourceController sourceCtrl) {
        sourceCtrl.focusMode = focusMode;
      }
      final isEmpty = widget.controller.text.isEmpty;

      final editorField = Stack(
        children: [
          AnimatedOpacity(
            opacity: isEmpty ? 1 : 0,
            duration: EditorMotion.duration(context, 130),
            curve: EditorMotion.curve,
            child: IgnorePointer(
              child: Text(
                'Empieza a escribir tus ideas aquí…',
                style: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.58),
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  height: 1.75,
                  fontStyle:
                      appearance.editorTypography == EditorTypography.serif
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          ),
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: _selectionGestureDetectorBuilder.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: EditableText(
                key: widget.editableKey,
                groupId: _tapRegionGroupId,
                controller: widget.controller,
                focusNode: widget.focusNode,
                scrollController: _scrollController,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  height: 1.75,
                  letterSpacing:
                      appearance.editorTypography == EditorTypography.sans
                      ? 0.1
                      : 0,
                  color: colors.onSurface,
                ),
                cursorColor: colors.primary,
                backgroundCursorColor: colors.onSurfaceVariant,
                cursorRadius: const Radius.circular(1.5),
                maxLines: null,
                expands: true,
                readOnly: false,
                showCursor: true,
                cursorWidth: 2.2,
                selectionColor: colors.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.38
                      : 0.22,
                ),
                selectionControls: desktopTextSelectionControls,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                onTapOutside: (_) {},
              ),
            ),
          ),
        ],
      );

      return RepaintBoundary(
        child: ColoredBox(
          color: colors.surfaceContainerLowest,
          child: Column(
            children: [
              EditorPanelHeader(
                title: 'EDITOR',
                focused: widget.focusNode.hasFocus,
                trailing: _QuickFormatStrip(
                  focusMode: focusMode,
                  outlineActive: widget.outlineActive,
                  onToggleFocus: appearance.toggleFocusMode,
                  onToggleOutline: widget.onToggleOutline,
                  onBold: () => _applyFormat(
                    () => MarkdownEditingAssistant.toggleWrap(
                      widget.controller,
                      '**',
                    ),
                  ),
                  onItalic: () => _applyFormat(
                    () => MarkdownEditingAssistant.toggleWrap(
                      widget.controller,
                      '*',
                    ),
                  ),
                  onCode: () => _applyFormat(
                    () => MarkdownEditingAssistant.toggleWrap(
                      widget.controller,
                      '`',
                    ),
                  ),
                  onTask: () => _applyFormat(
                    () => MarkdownEditingAssistant.toggleTaskLine(
                      widget.controller,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TapRegion(
                  groupId: _tapRegionGroupId,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (!widget.focusNode.hasFocus) {
                        widget.focusNode.requestFocus();
                      }
                    },
                    child: Scrollbar(
                      controller: _scrollController,
                      child: LayoutBuilder(
                        builder: (context, viewport) {
                          final bottomPadding = focusMode
                              ? (viewport.maxHeight * 0.42).clamp(24.0, 260.0)
                              : (widget.centered ? 20.0 : 16.0);
                          return Padding(
                            padding: widget.centered
                                ? EdgeInsets.fromLTRB(32, 18, 32, bottomPadding)
                                : EdgeInsets.fromLTRB(26, 12, 24, bottomPadding),
                            child: widget.centered
                                ? Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 740,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: double.infinity,
                                        child: editorField,
                                      ),
                                    ),
                                  )
                                : SizedBox.expand(child: editorField),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.linkSuggestions case final suggestions?)
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: suggestions,
                  ),
                ),
              _EditorStatusBar(controller: widget.controller),
            ],
          ),
        ),
      );
    },
  );
}

class _QuickFormatStrip extends StatelessWidget {
  const _QuickFormatStrip({
    required this.onBold,
    required this.onItalic,
    required this.onCode,
    required this.onTask,
    required this.focusMode,
    required this.outlineActive,
    required this.onToggleFocus,
    this.onToggleOutline,
  });

  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onCode;
  final VoidCallback onTask;
  final bool focusMode;
  final bool outlineActive;
  final VoidCallback onToggleFocus;
  final VoidCallback? onToggleOutline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FormatMiniButton(
          tooltip: 'Negrita (⌘B)',
          onPressed: onBold,
          child: Text(
            'B',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        _FormatMiniButton(
          tooltip: 'Cursiva (⌘I)',
          onPressed: onItalic,
          child: Text(
            'I',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        _FormatMiniButton(
          tooltip: 'Código en línea (⌘E)',
          onPressed: onCode,
          child: Icon(
            CupertinoIcons.chevron_left_slash_chevron_right,
            size: 14.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        _FormatMiniButton(
          tooltip: 'Casilla de tarea (⌘⇧L)',
          onPressed: onTask,
          child: Icon(
            CupertinoIcons.checkmark_square,
            size: 15.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
        _FormatMiniButton(
          tooltip: focusMode
              ? 'Desactivar Modo Enfoque (⌘⇧F)'
              : 'Modo Enfoque (⌘⇧F)',
          active: focusMode,
          onPressed: onToggleFocus,
          child: Icon(
            CupertinoIcons.scope,
            size: 15.5,
            color: focusMode ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        if (onToggleOutline != null)
          _FormatMiniButton(
            tooltip: outlineActive
                ? 'Ocultar índice y enlaces (⌘⇧O)'
                : 'Índice, etiquetas y enlaces (⌘⇧O)',
            active: outlineActive,
            onPressed: onToggleOutline!,
            child: Icon(
              CupertinoIcons.list_bullet_indent,
              size: 15.5,
              color: outlineActive ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _FormatMiniButton extends StatefulWidget {
  const _FormatMiniButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.active = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool active;

  @override
  State<_FormatMiniButton> createState() => _FormatMiniButtonState();
}

class _FormatMiniButtonState extends State<_FormatMiniButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: widget.onPressed,
          child: AnimatedContainer(
            duration: EditorMotion.duration(context, 120),
            width: 28,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.active
                  ? colors.primaryContainer.withValues(alpha: 0.85)
                  : _hovered
                  ? colors.surfaceContainerHigh
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _EditorStatusBar extends StatelessWidget {
  const _EditorStatusBar({required this.controller});

  final TextEditingController controller;

  String _readingStatsLabel(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '0 palabras';
    final words = trimmed.split(RegExp(r'\s+')).length;
    final minutes = (words / 200).ceil().clamp(1, 999);
    return '$words ${words == 1 ? 'palabra' : 'palabras'} · $minutes min';
  }

  String _positionLabel(TextEditingValue value) {
    final text = value.text;
    final offset = value.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, offset);
    final lines = before.split('\n');
    return 'Ln ${lines.length}, Col ${lines.last.length + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = controller.value;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final showHints = maxWidth >= 320;
          final showStats = maxWidth >= 460;
          return Row(
            children: [
              if (showHints)
                Expanded(
                  child: Text(
                    '⌃←/→ paneles · ⌘1/2/3 · ⌘B · ⌘I · ⌘⇧L',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (showStats) ...[
                const SizedBox(width: 8),
                Text(
                  _readingStatsLabel(value.text),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: TextStyle(fontSize: 11, color: colors.outline),
                  ),
                ),
              ] else
                const SizedBox(width: 6),
              Flexible(
                flex: 0,
                child: Text(
                  _positionLabel(value),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EditorPanelHeader extends StatelessWidget {
  const EditorPanelHeader({
    super.key,
    required this.title,
    this.trailing,
    this.preview = false,
    this.focused = false,
  });

  final String title;
  final Widget? trailing;
  final bool preview;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: style.isGraphic
          ? BoxDecoration(
              color: style.isPop && preview
                  ? colors.surfaceContainerHighest
                  : colors.surface,
              border: Border(bottom: BorderSide(color: style.ink)),
            )
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: EditorMotion.duration(context, 140),
            width: focused ? 6 : 0,
            height: 6,
            margin: EdgeInsets.only(right: focused ? 6 : 0),
            decoration: BoxDecoration(
              color: focused ? colors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: focused ? colors.onSurface : colors.onSurfaceVariant,
                fontFamily: style.isRetro ? 'Menlo' : null,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (trailing != null)
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: trailing!,
              ),
            ),
        ],
      ),
    );
  }
}
