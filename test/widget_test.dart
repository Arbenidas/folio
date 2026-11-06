import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/main.dart';
import 'package:folio/features/editor/data/file_repository.dart';
import 'package:folio/features/editor/domain/document_repository.dart';
import 'package:folio/features/editor/domain/markdown_document.dart';
import 'package:folio/features/editor/presentation/controllers/editor_notifier.dart';
import 'package:folio/features/editor/presentation/controllers/vim_controller.dart';
import 'package:folio/features/editor/presentation/views/editor_screen.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_preview.dart';

class MemoryRepository implements DocumentRepository {
  List<MarkdownDocument> saved = [
    const MarkdownDocument(
      id: '1',
      title: 'Flutter',
      content: '# Widgets\n\nMis apuntes',
    ),
  ];
  bool fail = false;
  @override
  Future<List<MarkdownDocument>> load() async => saved;
  @override
  Future<void> save(List<MarkdownDocument> notes) async {
    if (fail) throw const FileSystemException('Disco no disponible');
    saved = notes;
  }

  @override
  Future<MarkdownDocument?> importMarkdown() async => null;
  @override
  Future<bool> exportMarkdown(MarkdownDocument note) async => true;
}

VimController makeVim(
  TextEditingController text, {
  ValueChanged<String>? onEdit,
}) => VimController(
  text,
  onEdit: onEdit ?? (_) {},
  onSave: () {},
  onCommand: () {},
  onSearch: () {},
  onLeftPane: () {},
  onRightPane: () {},
);
void press(VimController vim, String char) => vim.handle(
  FocusNode(),
  KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: LogicalKeyboardKey.keyA,
    character: char,
    timeStamp: Duration.zero,
  ),
);

void main() {
  test(
    'Migrates old notes without changing the old notebook or its visuals',
    () async {
      final dir = await Directory.systemTemp.createTemp('apuntes-test-');
      try {
        final original = jsonEncode({
          'version': 1,
          'notes': [
            {'id': 'a', 'title': 'Mi nota', 'content': '**Importante**'},
          ],
          'visuals': [
            {'any': 'old visual'},
          ],
        });
        final old = File('${dir.path}/notebook.json');
        await old.writeAsString(original);
        final repo = FileRepository(directory: dir);
        final notes = await repo.load();
        expect(notes.single.content, '**Importante**');
        await repo.save([notes.single.copyWith(content: 'Editado')]);
        expect((await repo.load()).single.content, 'Editado');
        expect(await old.readAsString(), original);
        expect(await File('${dir.path}/notes.json.tmp').exists(), false);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('Invalid stored notes are not silently replaced', () async {
    final dir = await Directory.systemTemp.createTemp('apuntes-test-');
    try {
      await File('${dir.path}/notes.json').writeAsString('{broken');
      final c = EditorNotifier(FileRepository(directory: dir));
      await c.load();
      expect(c.loadFailed, true);
      await c.save();
      expect(await File('${dir.path}/notes.json').readAsString(), '{broken');
      c.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('Switching notes and serialized saving preserve each note', () async {
    final repo = MemoryRepository();
    final c = EditorNotifier(repo);
    await c.load();
    c.update(content: 'Primera');
    c.create();
    c.update(content: 'Segunda');
    await c.save();
    c.select('1');
    expect(c.note.content, 'Primera');
    expect(repo.saved.last.content, 'Segunda');
    repo.fail = true;
    c.update(content: 'Cambio pendiente');
    await c.save();
    expect(c.saveStatus, 'Error al guardar');
    c.dispose();
  });
  test('Vim handles words, line movement, Unicode deletion and undo', () {
    final text = TextEditingController();
    final vim = makeVim(text);
    vim.load('uno dos\nx\nuna linea larga');
    press(vim, 'w');
    expect(vim.cursor, 4);
    press(vim, 'j');
    expect(vim.cursor, 8);
    press(vim, 'j');
    expect(vim.cursor, 14);
    press(vim, 'g');
    press(vim, 'g');
    expect(vim.cursor, 0);
    press(vim, r'$');
    expect(vim.cursor, 6);
    vim.load('a🦋b');
    press(vim, 'l');
    press(vim, 'x');
    expect(text.text, 'ab');
    press(vim, 'u');
    expect(text.text, 'a🦋b');
    vim.dispose();
    text.dispose();
  });
  test('Vim line commands, insert and search maintain valid selections', () {
    final text = TextEditingController();
    final vim = makeVim(text);
    vim.load('uno\ndos\ntres');
    press(vim, 'd');
    press(vim, 'd');
    expect(text.text, 'dos\ntres');
    press(vim, 'p');
    expect(text.text, 'dos\nuno\ntres');
    expect(vim.search('tres'), true);
    expect(vim.cursor, 8);
    press(vim, 'o');
    expect(vim.insert, true);
    expect(text.text, 'dos\nuno\ntres\n');
    vim.load('');
    press(vim, 'h');
    press(vim, 'l');
    press(vim, 'b');
    press(vim, 'x');
    expect(vim.cursor, 0);
    vim.dispose();
    text.dispose();
  });
  testWidgets(
    'Sidebar transitions preserve editing state and keyboard scroll accumulates',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = EditorNotifier(MemoryRepository());
      await c.load();
      c.update(content: List.generate(100, (i) => 'Párrafo $i\n').join('\n'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final source = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.focusNode.debugLabel == 'Editor',
      );
      final original = tester.state<EditableTextState>(source);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL, character: 'l');
      await tester.pump();
      final selection = original.widget.controller.selection;
      final markdown = tester.widget<MarkdownPreview>(
        find.byType(MarkdownPreview),
      );
      final markdownState = tester.state(find.byType(MarkdownPreview));
      final initialX = tester.getTopLeft(source).dx;
      await tester.tap(find.byTooltip('Ocultar notas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final duringX = tester.getTopLeft(source).dx;
      expect(duringX, lessThan(initialX));
      expect(duringX, greaterThan(initialX - 206));
      expect(tester.takeException(), isNull);
      // Reverse while still moving; the source field must never be recreated.
      await tester.tap(find.byTooltip('Mostrar notas'));
      await tester.pumpAndSettle();
      expect(tester.state(source), same(original));
      expect(original.widget.controller.selection, selection);
      expect(tester.state(find.byType(MarkdownPreview)), same(markdownState));
      expect(
        tester.widget<MarkdownPreview>(find.byType(MarkdownPreview)).controller,
        same(markdown.controller),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ, character: 'j');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ, character: 'j');
      await tester.pumpAndSettle();
      expect(markdown.controller.offset, closeTo(60, 0.1));
      expect(tester.takeException(), isNull);
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Reduced motion collapses sidebar immediately without losing the editor',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final c = EditorNotifier(MemoryRepository());
      await c.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('EDITOR')).dx;
      await tester.tap(find.byTooltip('Ocultar notas'));
      await tester.pump();
      expect(tester.getTopLeft(find.text('EDITOR')).dx, before - 236);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Simple editor creates notes, renders Markdown, opens help and supports Vim',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = EditorNotifier(MemoryRepository());
      await c.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VISTA PREVIA'), findsOneWidget);
      expect(find.text('NORMAL'), findsOneWidget);
      expect(find.text('Estudio'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
      await tester.pump();
      expect(find.text('INSERT'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.focusNode.debugLabel == 'Editor',
        ),
        '# Flutter\n\nUn widget',
      );
      await tester.pumpAndSettle();
      expect(c.note.content, '# Flutter\n\nUn widget');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('NORMAL'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.notes.length, 2);
      expect(find.text('INSERT'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Markdown'), findsWidgets);
      expect(find.text('Títulos'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Cerrar ayuda'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
