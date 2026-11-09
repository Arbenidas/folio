import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Associates the renderer's task items with the original Markdown offsets.
class MarkdownTasks extends MarkdownPaddingBuilder {
  MarkdownTasks(this.source, this.onToggle) : _offsets = _taskOffsets(source);

  final String source;
  final ValueChanged<int>? onToggle;
  final List<int?> _offsets;
  int _next = 0;

  static final _line = RegExp(
    r'^[ \t]*(?:>[ \t]*)*(?:[-+*]|\d{1,9}[.)])[ \t]+\[[ xX]\](?=[ \t])',
    multiLine: true,
  );

  static md.Element? _input(md.Element item) {
    final first = item.children?.firstOrNull;
    if (first is! md.Element) return null;
    final input = first.tag == 'p' ? first.children?.firstOrNull : first;
    return input is md.Element && input.attributes['type'] == 'checkbox'
        ? input
        : null;
  }

  static List<int?> _taskOffsets(String source) {
    final matches = _line.allMatches(source).toList();
    if (matches.isEmpty) return [];
    var prefix = '\uE000folio';
    while (source.contains(prefix)) {
      prefix += '_';
    }
    // Parse a separate annotated copy. The parser discards candidates inside
    // code blocks and other constructs that don't render as tasks.
    final annotated = StringBuffer();
    var start = 0;
    for (final match in matches) {
      annotated
        ..write(source.substring(start, match.end))
        ..write(' $prefix${match.end - 2}\uE001');
      start = match.end;
    }
    annotated.write(source.substring(start));
    final marker = RegExp('$prefix(\\d+)\uE001');
    List<({bool checked, int? offset})> parse(String text) {
      final tasks = <({bool checked, int? offset})>[];
      void visit(md.Node node) {
        if (node is! md.Element) return;
        // The renderer builds the bullet after visiting nested list items.
        node.children?.forEach(visit);
        final input = node.tag == 'li' ? _input(node) : null;
        if (input != null) {
          final match = marker.matchAsPrefix(node.textContent.trimLeft());
          tasks.add((
            checked: input.attributes.containsKey('checked'),
            offset: match == null ? null : int.parse(match.group(1)!),
          ));
        }
      }

      md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parseLines(const LineSplitter().convert(text)).forEach(visit);
      return tasks;
    }

    final original = parse(source);
    final marked = parse(annotated.toString());
    if (original.length != marked.length) return [];
    return [
      for (var i = 0; i < marked.length; i++)
        marked[i].checked == original[i].checked ? marked[i].offset : null,
    ];
  }

  @override
  void visitElementBefore(md.Element element) {
    final input = _input(element);
    if (input == null) return;
    final children = element.children!;
    final first = children.first;
    final bullet = _TaskBullet(input);
    if (first is md.Element && first.tag == 'p') {
      // The renderer expects the input directly under the list item.
      first.children!.removeAt(0);
      children.insert(0, bullet);
    } else {
      children[0] = bullet;
    }
  }

  Widget checkbox(bool checked) {
    final offset = _offsets.isEmpty
        ? null
        : _offsets[_next++ % _offsets.length];
    final marker = offset == null ? null : source[offset];
    final valid = checked ? marker == 'x' || marker == 'X' : marker == ' ';
    return Material(
      type: MaterialType.transparency,
      child: Checkbox(
        value: checked,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: valid && onToggle != null ? (_) => onToggle!(offset!) : null,
      ),
    );
  }
}

// The list renderer reads the checkbox attributes as bullet metadata. It must
// not also visit this node as inline content before a nested paragraph.
class _TaskBullet extends md.Element {
  _TaskBullet(md.Element input) : super.withTag(input.tag) {
    attributes.addAll(input.attributes);
  }

  @override
  void accept(md.NodeVisitor visitor) {}
}
