import 'package:flutter/material.dart';

/// Styles Markdown source in-place without altering text, selection, or undo history.
/// Supports `#tags`, Focus Mode paragraph dimming, and O(1) span caching.
class MarkdownSourceController extends TextEditingController {
  bool focusMode = false;

  static final _headingPattern = RegExp(r'^( {0,3})(#{1,6})([ \t]+)(.*)$');
  static final _fencePattern = RegExp(r'^( {0,3})(`{3,}|~{3,})(.*)$');
  static final _quotePattern = RegExp(r'^( {0,3}>+[ \t]?)(.*)$');
  static final _taskPattern = RegExp(
    r'^( {0,6}[-*+][ \t]+)(\[[ xX]\])([ \t]+)(.*)$',
  );
  static final _listPattern = RegExp(r'^( {0,6}(?:[-*+]|\d+\.)[ \t]+)(.*)$');
  static final _hrPattern = RegExp(r'^ {0,3}(?:([-*_])(?:[ \t]*\1){2,})[ \t]*$');

  static final _inlinePattern = RegExp(
    r'(`[^`\n]+`)'
    r'|(\*\*[^*\n]+?\*\*|__[^_\n]+?__)'
    r'|(\*[^*\s][^*\n]*?\*|_[^_\s][^_\n]*?_)'
    r'|(~~[^~\n]+?~~)'
    r'|(\[[^\]\n]+\]\([^\)\n]+\))'
    r'|(\[\[[^\]\n]+\]\])'
    r'|((?:^|(?<=\s))#[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ][\wáéíóúÁÉÍÓÚñÑüÜ-]{0,31})',
  );

  String? _cachedText;
  int _cachedThemeHash = 0;
  TextStyle? _cachedBaseStyle;
  bool _cachedFocusMode = false;
  int _cachedFocusParaStart = -1;
  int _cachedFocusParaEnd = -1;
  List<InlineSpan>? _cachedChildren;

  (int, int) _activeParagraphBounds(String source) {
    if (!focusMode || source.isEmpty || !selection.isValid) {
      return (0, source.length);
    }
    final caret = selection.extentOffset.clamp(0, source.length);
    var pStart = 0;
    var searchFrom = caret > 0 ? caret - 1 : 0;
    while (searchFrom > 0) {
      final sep = source.lastIndexOf('\n\n', searchFrom);
      if (sep >= 0 && sep + 2 <= caret) {
        pStart = sep + 2;
        break;
      }
      if (sep < 0) break;
      searchFrom = sep - 1;
    }
    final nextSep = source.indexOf('\n\n', caret);
    final pEnd = nextSep < 0 ? source.length : nextSep + 1;
    return (pStart, pEnd);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing &&
        value.isComposingRangeValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final colors = Theme.of(context).colorScheme;
    final themeHash = Object.hash(
      colors.primary,
      colors.secondary,
      colors.tertiary,
      colors.onSurface,
      colors.onSurfaceVariant,
      colors.surfaceContainerHigh,
      colors.primaryContainer,
      colors.outline,
    );
    final (paraStart, paraEnd) = _activeParagraphBounds(text);

    if (identical(_cachedText, text) &&
        _cachedThemeHash == themeHash &&
        _cachedBaseStyle == style &&
        _cachedFocusMode == focusMode &&
        (!focusMode ||
            (_cachedFocusParaStart == paraStart &&
                _cachedFocusParaEnd == paraEnd)) &&
        _cachedChildren != null) {
      return TextSpan(style: style, children: _cachedChildren);
    }

    final children = _parseDocument(
      text,
      style,
      colors,
      focusMode: focusMode,
      activeStart: paraStart,
      activeEnd: paraEnd,
    );
    _cachedText = text;
    _cachedThemeHash = themeHash;
    _cachedBaseStyle = style;
    _cachedFocusMode = focusMode;
    _cachedFocusParaStart = paraStart;
    _cachedFocusParaEnd = paraEnd;
    _cachedChildren = children;
    return TextSpan(style: style, children: children);
  }

  List<InlineSpan> _parseDocument(
    String source,
    TextStyle? baseStyle,
    ColorScheme colors, {
    required bool focusMode,
    required int activeStart,
    required int activeEnd,
  }) {
    if (source.isEmpty) return const [];

    final baseSize = baseStyle?.fontSize ?? 14.5;
    final mutedMarker = TextStyle(
      color: colors.onSurfaceVariant.withValues(alpha: 0.58),
      fontWeight: FontWeight.w400,
    );
    final fenceStyle = TextStyle(
      color: colors.secondary,
      fontFamily: 'Menlo',
      fontSize: baseSize - 1,
    );
    final codeBlockStyle = TextStyle(
      color: colors.onSurface.withValues(alpha: 0.88),
      fontFamily: 'Menlo',
      fontSize: baseSize - 1,
      backgroundColor: colors.surfaceContainerLow.withValues(alpha: 0.85),
    );
    final inlineCodeStyle = TextStyle(
      fontFamily: 'Menlo',
      fontSize: baseSize - 1,
      color: colors.primary,
      backgroundColor: colors.surfaceContainerHigh.withValues(alpha: 0.72),
    );
    final tagStyle = TextStyle(
      color: colors.tertiary,
      fontWeight: FontWeight.w600,
      backgroundColor: colors.tertiaryContainer.withValues(alpha: 0.45),
    );
    final boldStyle = const TextStyle(fontWeight: FontWeight.w700);
    final italicStyle = const TextStyle(fontStyle: FontStyle.italic);
    final strikeStyle = TextStyle(
      decoration: TextDecoration.lineThrough,
      color: colors.onSurfaceVariant,
    );
    final linkLabelStyle = TextStyle(
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary.withValues(alpha: 0.45),
    );
    final linkUrlStyle = TextStyle(
      color: colors.onSurfaceVariant.withValues(alpha: 0.65),
    );
    final quoteStyle = TextStyle(
      color: colors.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    final bulletStyle = TextStyle(
      color: colors.primary,
      fontWeight: FontWeight.w700,
    );
    final hrStyle = TextStyle(color: colors.outline);
    final dimmedTextStyle = TextStyle(
      color: colors.onSurface.withValues(alpha: 0.30),
    );

    final spans = <InlineSpan>[];
    String? fenceChar;
    var fenceLen = 0;
    var start = 0;
    final length = source.length;

    while (start <= length) {
      final nl = source.indexOf('\n', start);
      final end = nl < 0 ? length : nl;
      final line = source.substring(start, end);
      final trailing = nl < 0 ? '' : '\n';
      final isDimmed =
          focusMode && (end < activeStart || start > activeEnd);

      final fenceMatch = _fencePattern.firstMatch(line);
      if (fenceChar != null) {
        if (fenceMatch != null) {
          final marker = fenceMatch.group(2)!;
          final rest = fenceMatch.group(3)!;
          if (marker.startsWith(fenceChar) &&
              marker.length >= fenceLen &&
              rest.trim().isEmpty) {
            fenceChar = null;
            fenceLen = 0;
            spans.add(
              TextSpan(
                text: '$line$trailing',
                style: isDimmed ? dimmedTextStyle : fenceStyle,
              ),
            );
          } else {
            spans.add(
              TextSpan(
                text: '$line$trailing',
                style: isDimmed ? dimmedTextStyle : codeBlockStyle,
              ),
            );
          }
        } else {
          spans.add(
            TextSpan(
              text: '$line$trailing',
              style: isDimmed ? dimmedTextStyle : codeBlockStyle,
            ),
          );
        }
      } else if (fenceMatch != null) {
        final marker = fenceMatch.group(2)!;
        fenceChar = marker[0];
        fenceLen = marker.length;
        spans.add(
          TextSpan(
            text: '$line$trailing',
            style: isDimmed ? dimmedTextStyle : fenceStyle,
          ),
        );
      } else if (isDimmed) {
        // Keep exact typography metrics for headings even while dimmed so text never jumps.
        if (_headingPattern.firstMatch(line) case final h?) {
          final level = h.group(2)!.length;
          final sizeBoost = switch (level) {
            1 => 5.5,
            2 => 3.5,
            3 => 2.0,
            4 => 1.0,
            _ => 0.0,
          };
          spans.add(
            TextSpan(
              text: '$line$trailing',
              style: dimmedTextStyle.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: baseSize + sizeBoost,
                letterSpacing: level <= 2 ? -0.3 : 0,
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: '$line$trailing', style: dimmedTextStyle));
        }
      } else if (_hrPattern.hasMatch(line)) {
        spans.add(TextSpan(text: '$line$trailing', style: hrStyle));
      } else if (_headingPattern.firstMatch(line) case final h?) {
        final indent = h.group(1)!;
        final hashes = h.group(2)!;
        final space = h.group(3)!;
        final body = h.group(4)!;
        final level = hashes.length;
        final sizeBoost = switch (level) {
          1 => 5.5,
          2 => 3.5,
          3 => 2.0,
          4 => 1.0,
          _ => 0.0,
        };
        final headingStyle = TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: baseSize + sizeBoost,
          letterSpacing: level <= 2 ? -0.3 : 0,
        );
        if (indent.isNotEmpty) spans.add(TextSpan(text: indent));
        spans.add(
          TextSpan(
            text: '$hashes$space',
            style: headingStyle.copyWith(
              color: colors.primary.withValues(alpha: 0.42),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
        spans.add(TextSpan(text: '$body$trailing', style: headingStyle));
      } else if (_quotePattern.firstMatch(line) case final q?) {
        spans.add(
          TextSpan(
            text: q.group(1)!,
            style: TextStyle(
              color: colors.primary.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        _appendInline(
          spans,
          '${q.group(2)!}$trailing',
          baseOverride: quoteStyle,
          mutedMarker: mutedMarker,
          inlineCodeStyle: inlineCodeStyle,
          boldStyle: boldStyle,
          italicStyle: italicStyle,
          strikeStyle: strikeStyle,
          linkLabelStyle: linkLabelStyle,
          linkUrlStyle: linkUrlStyle,
          tagStyle: tagStyle,
        );
      } else if (_taskPattern.firstMatch(line) case final t?) {
        final checked = t.group(2) != '[ ]';
        spans.add(TextSpan(text: t.group(1)!, style: bulletStyle));
        spans.add(
          TextSpan(
            text: t.group(2)!,
            style: TextStyle(
              color: checked ? colors.primary : colors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        spans.add(TextSpan(text: t.group(3)!));
        _appendInline(
          spans,
          '${t.group(4)!}$trailing',
          baseOverride: checked
              ? TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                  decoration: TextDecoration.lineThrough,
                )
              : null,
          mutedMarker: mutedMarker,
          inlineCodeStyle: inlineCodeStyle,
          boldStyle: boldStyle,
          italicStyle: italicStyle,
          strikeStyle: strikeStyle,
          linkLabelStyle: linkLabelStyle,
          linkUrlStyle: linkUrlStyle,
          tagStyle: tagStyle,
        );
      } else if (_listPattern.firstMatch(line) case final l?) {
        spans.add(TextSpan(text: l.group(1)!, style: bulletStyle));
        _appendInline(
          spans,
          '${l.group(2)!}$trailing',
          mutedMarker: mutedMarker,
          inlineCodeStyle: inlineCodeStyle,
          boldStyle: boldStyle,
          italicStyle: italicStyle,
          strikeStyle: strikeStyle,
          linkLabelStyle: linkLabelStyle,
          linkUrlStyle: linkUrlStyle,
          tagStyle: tagStyle,
        );
      } else {
        _appendInline(
          spans,
          '$line$trailing',
          mutedMarker: mutedMarker,
          inlineCodeStyle: inlineCodeStyle,
          boldStyle: boldStyle,
          italicStyle: italicStyle,
          strikeStyle: strikeStyle,
          linkLabelStyle: linkLabelStyle,
          linkUrlStyle: linkUrlStyle,
          tagStyle: tagStyle,
        );
      }

      if (nl < 0) break;
      start = nl + 1;
    }

    return spans;
  }

  void _appendInline(
    List<InlineSpan> spans,
    String segment, {
    TextStyle? baseOverride,
    required TextStyle mutedMarker,
    required TextStyle inlineCodeStyle,
    required TextStyle boldStyle,
    required TextStyle italicStyle,
    required TextStyle strikeStyle,
    required TextStyle linkLabelStyle,
    required TextStyle linkUrlStyle,
    required TextStyle tagStyle,
  }) {
    if (segment.isEmpty) return;
    if (!segment.contains('*') &&
        !segment.contains('_') &&
        !segment.contains('`') &&
        !segment.contains('~') &&
        !segment.contains('[') &&
        !segment.contains('#')) {
      spans.add(TextSpan(text: segment, style: baseOverride));
      return;
    }

    var cursor = 0;
    for (final match in _inlinePattern.allMatches(segment)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: segment.substring(cursor, match.start),
            style: baseOverride,
          ),
        );
      }
      final raw = match.group(0)!;
      if (match.group(1) != null) {
        spans.add(TextSpan(text: '`', style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(1, raw.length - 1),
            style: inlineCodeStyle,
          ),
        );
        spans.add(TextSpan(text: '`', style: mutedMarker));
      } else if (match.group(2) != null) {
        final delim = raw.substring(0, 2);
        spans.add(TextSpan(text: delim, style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(2, raw.length - 2),
            style: baseOverride == null
                ? boldStyle
                : baseOverride.merge(boldStyle),
          ),
        );
        spans.add(TextSpan(text: delim, style: mutedMarker));
      } else if (match.group(3) != null) {
        final delim = raw.substring(0, 1);
        spans.add(TextSpan(text: delim, style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(1, raw.length - 1),
            style: baseOverride == null
                ? italicStyle
                : baseOverride.merge(italicStyle),
          ),
        );
        spans.add(TextSpan(text: delim, style: mutedMarker));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: '~~', style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(2, raw.length - 2),
            style: strikeStyle,
          ),
        );
        spans.add(TextSpan(text: '~~', style: mutedMarker));
      } else if (match.group(5) != null) {
        final closeBracket = raw.indexOf('](');
        spans.add(TextSpan(text: '[', style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(1, closeBracket),
            style: linkLabelStyle,
          ),
        );
        spans.add(
          TextSpan(text: raw.substring(closeBracket), style: linkUrlStyle),
        );
      } else if (match.group(6) != null) {
        spans.add(TextSpan(text: '[[', style: mutedMarker));
        spans.add(
          TextSpan(
            text: raw.substring(2, raw.length - 2),
            style: linkLabelStyle,
          ),
        );
        spans.add(TextSpan(text: ']]', style: mutedMarker));
      } else if (match.group(7) != null) {
        spans.add(TextSpan(text: raw, style: tagStyle));
      }
      cursor = match.end;
    }

    if (cursor < segment.length) {
      spans.add(TextSpan(text: segment.substring(cursor), style: baseOverride));
    }
  }
}
