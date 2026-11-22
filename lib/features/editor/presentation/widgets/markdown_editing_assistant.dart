import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Smart Markdown editing ergonomics: list/quote continuation, indentation,
/// selection wrapping, and standard formatting shortcuts (Cmd+B/I/E/Shift+X/L).
abstract final class MarkdownEditingAssistant {
  static final _taskLine = RegExp(r'^([ \t]*)([-*+]) \[[ xX]\] (.*)$');
  static final _bulletLine = RegExp(r'^([ \t]*)([-*+]) (.*)$');
  static final _orderedLine = RegExp(r'^([ \t]*)(\d+)\. (.*)$');
  static final _quoteLine = RegExp(r'^([ \t]*>+[ \t]*)(.*)$');

  static const _wrapPairs = {
    '*': '*',
    '_': '_',
    '`': '`',
    '~': '~',
    '[': ']',
    '(': ')',
    '"': '"',
  };

  /// Handles Markdown ergonomic keys while in insert / normal text mode.
  static KeyEventResult handleKey(
    TextEditingController controller,
    KeyEvent event, {
    required bool isWriting,
  }) {
    if (!isWriting || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final selection = controller.selection;
    if (!selection.isValid) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;

    // Formatting shortcuts with Cmd.
    if (keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.keyB && !keyboard.isShiftPressed) {
        toggleWrap(controller, '**');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI && !keyboard.isShiftPressed) {
        toggleWrap(controller, '*');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE && !keyboard.isShiftPressed) {
        toggleWrap(controller, '`');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX && keyboard.isShiftPressed) {
        toggleWrap(controller, '~~');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL && keyboard.isShiftPressed) {
        toggleTaskLine(controller);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (keyboard.isControlPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    // Smart Enter for lists, tasks, and blockquotes.
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !keyboard.isShiftPressed &&
        selection.isCollapsed) {
      if (_handleSmartEnter(controller)) return KeyEventResult.handled;
    }

    // Smart Tab / Shift+Tab for indentation.
    if (key == LogicalKeyboardKey.tab) {
      _indentSelection(controller, outdent: keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }

    // Wrap selected text with pairing delimiter when user types *, _, `, [, (, "
    final char = event.character;
    if (!selection.isCollapsed &&
        char != null &&
        _wrapPairs.containsKey(char)) {
      wrapSelection(controller, char, _wrapPairs[char]!);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  static bool _handleSmartEnter(TextEditingController controller) {
    final text = controller.text;
    final caret = controller.selection.extentOffset;
    if (caret < 0 || caret > text.length) return false;
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final beforeCaret = text.substring(lineStart, caret);

    String? nextPrefix;
    var emptyItem = false;

    if (_taskLine.firstMatch(beforeCaret) case final m?) {
      emptyItem = m.group(3)!.trim().isEmpty;
      nextPrefix = '${m.group(1)!}${m.group(2)!} [ ] ';
    } else if (_bulletLine.firstMatch(beforeCaret) case final m?) {
      emptyItem = m.group(3)!.trim().isEmpty;
      nextPrefix = '${m.group(1)!}${m.group(2)!} ';
    } else if (_orderedLine.firstMatch(beforeCaret) case final m?) {
      emptyItem = m.group(3)!.trim().isEmpty;
      final nextNumber = (int.tryParse(m.group(2)!) ?? 1) + 1;
      nextPrefix = '${m.group(1)!}$nextNumber. ';
    } else if (_quoteLine.firstMatch(beforeCaret) case final m?) {
      emptyItem = m.group(2)!.trim().isEmpty;
      nextPrefix = m.group(1)!;
    }

    if (nextPrefix == null) return false;

    if (emptyItem) {
      // Pressing Enter on an empty list/quote line exits the list cleanly.
      final updated = text.replaceRange(lineStart, caret, '');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: lineStart),
      );
      return true;
    }

    final insertion = '\n$nextPrefix';
    final updated = text.replaceRange(caret, caret, insertion);
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: caret + insertion.length),
    );
    return true;
  }

  static void _indentSelection(
    TextEditingController controller, {
    required bool outdent,
  }) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);

    if (sel.isCollapsed && !outdent) {
      final updated = text.replaceRange(start, end, '  ');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: start + 2),
      );
      return;
    }

    final firstLineStart = start == 0
        ? 0
        : text.lastIndexOf('\n', start - 1) + 1;
    final block = text.substring(firstLineStart, end);
    final lines = block.split('\n');
    var firstDelta = 0;
    var totalDelta = 0;
    final replaced = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (outdent) {
        if (line.startsWith('  ')) {
          replaced.add(line.substring(2));
          if (i == 0) firstDelta = -2;
          totalDelta -= 2;
        } else if (line.startsWith('\t') || line.startsWith(' ')) {
          replaced.add(line.substring(1));
          if (i == 0) firstDelta = -1;
          totalDelta -= 1;
        } else {
          replaced.add(line);
        }
      } else {
        replaced.add('  $line');
        if (i == 0) firstDelta = 2;
        totalDelta += 2;
      }
    }

    final updatedBlock = replaced.join('\n');
    final updated = text.replaceRange(firstLineStart, end, updatedBlock);
    final nextStart = (start + firstDelta).clamp(
      firstLineStart,
      updated.length,
    );
    final nextEnd = (end + totalDelta).clamp(nextStart, updated.length);
    controller.value = TextEditingValue(
      text: updated,
      selection: sel.isCollapsed
          ? TextSelection.collapsed(offset: nextEnd)
          : TextSelection(baseOffset: nextStart, extentOffset: nextEnd),
    );
  }

  static void toggleWrap(TextEditingController controller, String marker) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final mLen = marker.length;

    if (sel.isCollapsed) {
      final updated = text.replaceRange(start, end, '$marker$marker');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: start + mLen),
      );
      return;
    }

    // Unwrap if already wrapped right around selection.
    if (start >= mLen &&
        end + mLen <= text.length &&
        text.substring(start - mLen, start) == marker &&
        text.substring(end, end + mLen) == marker) {
      final inner = text.substring(start, end);
      final updated = text.replaceRange(start - mLen, end + mLen, inner);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: start - mLen,
          extentOffset: end - mLen,
        ),
      );
      return;
    }

    wrapSelection(controller, marker, marker);
  }

  static void wrapSelection(
    TextEditingController controller,
    String left,
    String right,
  ) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final updated = text.replaceRange(start, end, '$left$selected$right');
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: end + left.length,
      ),
    );
  }

  static void toggleTaskLine(TextEditingController controller) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    final caret = sel.extentOffset.clamp(0, text.length);
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final lineEndIndex = text.indexOf('\n', caret);
    final lineEnd = lineEndIndex < 0 ? text.length : lineEndIndex;
    final line = text.substring(lineStart, lineEnd);

    if (line.startsWith('- [ ] ')) {
      final updated = text.replaceRange(lineStart, lineStart + 6, '- [x] ');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: caret),
      );
    } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
      final updated = text.replaceRange(lineStart, lineStart + 6, '');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: (caret - 6).clamp(lineStart, updated.length),
        ),
      );
    } else {
      final updated = text.replaceRange(lineStart, lineStart, '- [ ] ');
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: caret + 6),
      );
    }
  }
}
