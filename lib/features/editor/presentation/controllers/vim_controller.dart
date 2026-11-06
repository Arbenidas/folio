import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Un subconjunto explícito de Vim; no intenta ejecutar ni emular Neovim completo.
class VimController extends ChangeNotifier {
  VimController(
    this.text, {
    required this.onEdit,
    required this.onSave,
    required this.onCommand,
    required this.onSearch,
    required this.onLeftPane,
    required this.onRightPane,
  }) {
    _previous = text.value;
    text.addListener(_changed);
  }
  final TextEditingController text;
  final ValueChanged<String> onEdit;
  final VoidCallback onSave, onCommand, onSearch, onLeftPane, onRightPane;
  bool enabled = true;
  bool insert = false;
  String _pending = '';
  String _register = '';
  String lastSearch = '';
  String? message;
  String? lastKey;
  int? _column;
  late TextEditingValue _previous;
  final List<TextEditingValue> _undo = [], _redo = [];
  bool _restoring = false, _loading = false;
  String get mode => !enabled
      ? 'TEXTO'
      : insert
      ? 'INSERT'
      : 'NORMAL';
  int get cursor => text.selection.isValid
      ? text.selection.extentOffset.clamp(0, text.text.length)
      : 0;
  String get position =>
      'L ${'\n'.allMatches(text.text.substring(0, cursor)).length + 1} · C ${text.text.substring(_start(cursor), cursor).characters.length + 1}';

  void _changed() {
    if (_previous.text != text.text) {
      if (!_restoring && !_loading) {
        _undo.add(_previous);
        if (_undo.length > 200) _undo.removeAt(0);
        _redo.clear();
      }
      if (!_loading) onEdit(text.text);
    }
    _previous = text.value;
    notifyListeners();
  }

  void load(String content) {
    _loading = true;
    text.value = TextEditingValue(
      text: content,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _loading = false;
    _undo.clear();
    _redo.clear();
    _pending = '';
    _column = null;
    insert = !enabled;
    message = null;
    notifyListeners();
  }

  void beginInsert() {
    insert = true;
    _pending = '';
    notifyListeners();
  }

  void toggle() {
    enabled = !enabled;
    insert = !enabled;
    _pending = '';
    notifyListeners();
  }

  int _start(int offset) =>
      offset <= 0 ? 0 : text.text.lastIndexOf('\n', offset - 1) + 1;
  int _end(int offset) {
    final i = text.text.indexOf('\n', offset);
    return i < 0 ? text.text.length : i;
  }

  List<int> get _boundaries {
    var n = 0;
    return [0, ...text.text.characters.map((char) => n += char.length)];
  }

  int _left(int offset) =>
      _boundaries.lastWhere((x) => x < offset, orElse: () => 0);
  int _right(int offset) =>
      _boundaries.firstWhere((x) => x > offset, orElse: () => text.text.length);
  void _move(int offset, {bool vertical = false}) {
    if (!vertical) _column = null;
    text.selection = TextSelection.collapsed(
      offset: offset.clamp(0, text.text.length),
    );
  }

  void _vertical(int direction) {
    final start = _start(cursor);
    final desired =
        _column ?? text.text.substring(start, cursor).characters.length;
    final targetStart = direction < 0
        ? (start == 0 ? 0 : _start(start - 1))
        : (_end(cursor) < text.text.length ? _end(cursor) + 1 : start);
    final end = _end(targetStart);
    final chars = text.text.substring(targetStart, end).characters.toList();
    final count = desired.clamp(0, chars.isEmpty ? 0 : chars.length - 1);
    _column = desired;
    _move(targetStart + chars.take(count).join().length, vertical: true);
  }

  int _category(String char) => char.trim().isEmpty
      ? 0
      : RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char)
      ? 1
      : 2;
  String _at(int offset) => text.text.substring(offset, _right(offset));
  void _word(bool backwards) {
    var i = cursor;
    if (backwards) {
      i = _left(i);
      while (i > 0 && _category(_at(i)) == 0) {
        i = _left(i);
      }
      final category = i < text.text.length ? _category(_at(i)) : 0;
      while (i > 0 && _category(_at(_left(i))) == category) {
        i = _left(i);
      }
    } else if (i < text.text.length) {
      final category = _category(_at(i));
      while (i < text.text.length && _category(_at(i)) == category) {
        i = _right(i);
      }
      while (i < text.text.length && _category(_at(i)) == 0) {
        i = _right(i);
      }
    }
    _move(i);
  }

  void _replace(int start, int end, String replacement, {int? caret}) {
    final value = text.text.replaceRange(start, end, replacement);
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(
        offset: (caret ?? start).clamp(0, value.length),
      ),
    );
    _column = null;
  }

  void _line(bool delete) {
    var start = _start(cursor);
    var end = _end(cursor);
    _register = '${text.text.substring(start, end)}\n';
    if (!delete) {
      message = 'Línea copiada';
      notifyListeners();
      return;
    }
    if (end < text.text.length) {
      end++;
    } else if (start > 0) {
      start--;
    }
    _replace(start, end, '');
  }

  void undo({bool redo = false}) {
    final from = redo ? _redo : _undo;
    final to = redo ? _undo : _redo;
    if (from.isEmpty) return;
    to.add(text.value);
    _restoring = true;
    text.value = from.removeLast();
    _restoring = false;
  }

  bool search(String query, {bool backwards = false}) {
    if (query.isEmpty) return false;
    lastSearch = query;
    final value = text.text;
    var match = backwards
        ? (cursor > 0 ? value.lastIndexOf(query, cursor - 1) : -1)
        : value.indexOf(query, (cursor + 1).clamp(0, value.length));
    if (match < 0) {
      match = backwards ? value.lastIndexOf(query) : value.indexOf(query);
    }
    if (match < 0) {
      message = 'No se encontró «$query»';
      notifyListeners();
      return false;
    }
    message = '/$query';
    _move(match);
    return true;
  }

  KeyEventResult handle(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.character != null && event.character!.trim().isNotEmpty) {
      lastKey = event.character;
    } else {
      lastKey = switch (event.logicalKey) {
        LogicalKeyboardKey.space => 'Space',
        LogicalKeyboardKey.enter => 'Enter',
        LogicalKeyboardKey.backspace => '⌫',
        LogicalKeyboardKey.tab => 'Tab',
        LogicalKeyboardKey.escape => 'Esc',
        _ => null,
      };
    }
    if (!enabled) {
      notifyListeners();
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (insert && cursor > _start(cursor)) _move(_left(cursor));
      insert = false;
      _pending = '';
      notifyListeners();
      return KeyEventResult.handled;
    }
    if (insert) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyR) {
        undo(redo: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyH) {
        onLeftPane();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        onRightPane();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final char = event.character;
    message = null;
    if (_pending.isNotEmpty) {
      final pending = _pending;
      _pending = '';
      if (pending == char) {
        if (char == 'g') _move(0);
        if (char == 'd') _line(true);
        if (char == 'y') _line(false);
        notifyListeners();
        return KeyEventResult.handled;
      }
    }
    switch (char) {
      case 'h':
        _move(_left(cursor).clamp(_start(cursor), text.text.length));
      case 'l':
        final end = _end(cursor);
        _move(
          _right(cursor)
              .clamp(_start(cursor), end > _start(cursor) ? _left(end) : end),
        );
      case 'j':
        _vertical(1);
      case 'k':
        _vertical(-1);
      case 'w':
        _word(false);
      case 'b':
        _word(true);
      case '0':
        _move(_start(cursor));
      case r'$':
        final end = _end(cursor);
        _move(end > _start(cursor) ? _left(end) : end);
      case 'g':
      case 'd':
      case 'y':
        _pending = char!;
      case 'G':
        _move(_start(text.text.length));
      case 'i':
        insert = true;
      case 'a':
        _move(_right(cursor).clamp(0, _end(cursor)));
        insert = true;
      case 'I':
        _move(_start(cursor));
        insert = true;
      case 'A':
        _move(_end(cursor));
        insert = true;
      case 'o':
        final end = _end(cursor);
        _replace(end, end, '\n', caret: end + 1);
        insert = true;
      case 'O':
        final start = _start(cursor);
        _replace(start, start, '\n', caret: start);
        insert = true;
      case 'x':
        if (cursor < _end(cursor)) _replace(cursor, _right(cursor), '');
      case 'u':
        undo();
      case 'p':
        if (_register.isNotEmpty) {
          final end = _end(cursor);
          final atEnd = end == text.text.length;
          final pos = atEnd ? end : end + 1;
          final value = atEnd && text.text.isNotEmpty
              ? '\n${_register.substring(0, _register.length - 1)}'
              : _register;
          _replace(
            pos,
            pos,
            value,
            caret: atEnd && text.text.isNotEmpty ? pos + 1 : pos,
          );
        }
      case '/':
        onSearch();
      case 'n':
        search(lastSearch);
      case 'N':
        search(lastSearch, backwards: true);
      case ':':
        onCommand();
      default:
        if (key == LogicalKeyboardKey.arrowDown) {
          _vertical(1);
        } else if (key == LogicalKeyboardKey.arrowUp) {
          _vertical(-1);
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          _move(_left(cursor));
        } else if (key == LogicalKeyboardKey.arrowRight) {
          _move(_right(cursor));
        } else if (char == null) {
          return KeyEventResult.ignored;
        }
    }
    notifyListeners();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    text.removeListener(_changed);
    super.dispose();
  }
}
