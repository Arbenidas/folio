import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart'
    show CupertinoSearchTextField, CupertinoTextField;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/main.dart';
import 'package:folio/core/theme.dart';
import 'package:folio/core/widgets/app_icon_button.dart';
import 'package:folio/features/editor/data/file_repository.dart';
import 'package:folio/features/editor/domain/document_repository.dart';
import 'package:folio/features/editor/domain/markdown_document.dart';
import 'package:folio/features/editor/domain/notebook_snapshot.dart';
import 'package:folio/features/editor/domain/trashed_note.dart';
import 'package:folio/features/editor/data/recovered_drafts_repository.dart';
import 'package:folio/features/editor/presentation/controllers/editor_notifier.dart';
import 'package:folio/features/editor/presentation/controllers/vim_controller.dart';
import 'package:folio/features/editor/presentation/views/editor_screen.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_preview.dart';
import 'package:folio/features/editor/presentation/widgets/notes_sidebar.dart';
import 'package:macos_ui/macos_ui.dart' show MacosTheme;

class MemoryRepository implements DocumentRepository {
  List<MarkdownDocument> saved = [
    const MarkdownDocument(
      id: '1',
      title: 'Flutter',
      content: '# Widgets\n\nMis apuntes',
    ),
  ];
  bool fail = false;
  final folders = <String>{};
  final events = StreamController<void>.broadcast();
  @override
  Future<NotebookSnapshot> load() async =>
      NotebookSnapshot(notes: saved, folderPaths: folders);
  @override
  Future<NotebookSnapshot> scan() => load();
  @override
  Stream<void> watch() => events.stream;
  @override
  Future<MarkdownDocument> createNote({
    String title = 'Nueva nota',
    String? folder,
    String content = '',
  }) async {
    final id = folder == null ? '$title.md' : '$folder/$title.md';
    final note = MarkdownDocument(
      id: id,
      title: title,
      content: content,
      folder: folder,
    );
    saved = [...saved, note];
    return note;
  }

  @override
  Future<MarkdownDocument> saveNote(MarkdownDocument note) async {
    if (fail) throw const FileSystemException('Disco no disponible');
    saved = [...saved.where((item) => item.id != note.id), note];
    return note;
  }

  @override
  Future<MarkdownDocument> renameNote(String id, String title) async {
    final old = saved.firstWhere((item) => item.id == id);
    final renamed = MarkdownDocument(
      id: '${old.folder == null ? '' : '${old.folder}/'}$title.md',
      title: title,
      content: old.content,
      folder: old.folder,
    );
    saved = [...saved.where((item) => item.id != id), renamed];
    return renamed;
  }

  @override
  Future<MarkdownDocument> moveNote(String id, String? folder) async {
    final old = saved.firstWhere((item) => item.id == id);
    final moved = MarkdownDocument(
      id: '${folder == null ? '' : '$folder/'}${old.title}.md',
      title: old.title,
      content: old.content,
      folder: folder,
    );
    saved = [...saved.where((item) => item.id != id), moved];
    return moved;
  }

  @override
  Future<void> deleteNote(String id) async =>
      saved = saved.where((item) => item.id != id).toList();
  @override
  Future<List<TrashedNote>> listTrash() async => [];
  @override
  Future<MarkdownDocument> restoreDeletedNote(String trashId) async =>
      throw UnsupportedError('No trash in this test repository.');
  final images = <String, Uint8List>{};
  @override
  Future<String> saveImage(String noteId, Uint8List png) async {
    const reference = '.folio-assets/0123456789abcdef0123456789abcdef.png';
    images[reference] = png;
    return reference;
  }

  @override
  Future<Uint8List?> readImage(String noteId, String reference) async =>
      images[reference];
  @override
  Future<String> createFolder(String path) async {
    folders.add(path);
    return path;
  }

  @override
  Future<String> renameFolder(String path, String title) async =>
      path.replaceFirst(RegExp(r'[^/]+$'), title);

  @override
  Future<String> moveFolder(String path, String? destination) async => path;
  @override
  Future<void> deleteFolder(String path) async => folders.remove(path);

  void replaceExternally(MarkdownDocument note) {
    saved = [...saved.where((item) => item.id != note.id), note];
    events.add(null);
  }

  @override
  Future<MarkdownDocument?> importMarkdown() async => null;
  @override
  Future<bool> exportMarkdown(MarkdownDocument note) async => true;
}

class EmptyRecoveredDrafts extends RecoveredDraftsRepository {
  @override
  Future<List<RecoveredDraft>> list() async => [];
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
        expect(notes.notes, isEmpty);
        expect(await old.readAsString(), original);
        final created = await repo.createNote(
          title: 'Mi nota',
          content: '**Importante**',
        );
        final markdown = File('${dir.path}/Folio/Mi nota.md');
        expect(await markdown.readAsString(), '**Importante**');
        await repo.saveNote(created.copyWith(content: 'Editado'));
        expect((await repo.load()).notes.single.content, 'Editado');
        await markdown.writeAsString('**Desde otro editor**');
        expect(
          (await repo.load()).notes.single.content,
          '**Desde otro editor**',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Unreadable legacy JSON does not block a new Markdown notebook',
    () async {
      final dir = await Directory.systemTemp.createTemp('apuntes-test-');
      try {
        await File('${dir.path}/notes.json').writeAsString('{broken');
        final c = EditorNotifier(FileRepository(directory: dir));
        await c.load();
        expect(c.loadFailed, false);
        expect(c.notes, isEmpty);
        expect(await File('${dir.path}/notes.json').readAsString(), '{broken');
        c.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('Switching notes and serialized saving preserve each note', () async {
    final repo = MemoryRepository();
    final c = EditorNotifier(repo);
    await c.load();
    c.update(content: 'Primera');
    await c.create();
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
    await repo.events.close();
  });
  test('External edits preserve dirty Markdown in private recovery', () async {
    final support = await Directory.systemTemp.createTemp('folio-conflict-');
    final repo = MemoryRepository();
    final c = EditorNotifier(
      repo,
      recovered: RecoveredDraftsRepository(directory: support),
    );
    await c.load();
    c.update(content: 'Edición local sin guardar');
    repo.replaceExternally(
      repo.saved.single.copyWith(content: 'Cambio externo'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 320));

    expect(c.notes.single.content, 'Cambio externo');
    expect(c.recoveredDrafts.single.content, 'Edición local sin guardar');
    c.dispose();
    await repo.events.close();
    await support.delete(recursive: true);
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
      final c = EditorNotifier(
        MemoryRepository(),
        recovered: EmptyRecoveredDrafts(),
      );
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
      final c = EditorNotifier(
        MemoryRepository(),
        recovered: EmptyRecoveredDrafts(),
      );
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
    'Quick search fades in place and updates contrast with the Folio theme',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      const channel = MethodChannel('apuntes/keyboard');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final appearance = AppAppearance.instance;
      final originalTheme = appearance.selected;
      addTearDown(() {
        appearance.selected = originalTheme;
        messenger.setMockMethodCallHandler(channel, null);
      });
      final c = EditorNotifier(
        MemoryRepository(),
        recovered: EmptyRecoveredDrafts(),
      );
      await c.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      final search = find.byType(CupertinoSearchTextField);
      final position = tester.getTopLeft(search);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(search), position);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(search), position);

      for (final theme in AppTheme.values) {
        appearance.choose(theme);
        await tester.pumpAndSettle();
        final colors = buildEditorTheme(theme).colorScheme;
        expect(
          MacosTheme.of(tester.element(search)).canvasColor,
          colors.surface,
        );
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
          colors.surfaceContainerLow,
        );
        final field = tester.widget<CupertinoSearchTextField>(search);
        expect(
          (field.decoration as BoxDecoration).color,
          colors.surfaceContainerLowest,
        );
        expect(field.style?.color, colors.onSurface);
        expect(field.placeholderStyle?.color, colors.onSurfaceVariant);
        final preview = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        expect(preview.styleSheet?.code?.color, colors.onSurface);
      }
      await tester.enterText(search, 'apuntes');
      await tester.pump();
      expect(
        find.textContaining('Mis apuntes', findRichText: true),
        findsWidgets,
      );
      c.update(content: 'Inicio\n\n${c.note.content}');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(c.selectedNote?.title, 'Flutter');
      final editor = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.focusNode.debugLabel == 'Editor',
        ),
      );
      expect(
        editor.controller.selection.extentOffset,
        c.note.content.indexOf('apuntes'),
      );
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Sidebar renames the clicked note by double click or context menu',
    (tester) async {
      final repository = MemoryRepository();
      await repository.createNote(title: 'Otra nota', content: 'Texto intacto');
      final c = EditorNotifier(repository, recovered: EmptyRecoveredDrafts());
      await c.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(NotesSidebar);
      final other = find.descendant(
        of: sidebar,
        matching: find.text('Otra nota'),
      );
      await tester.tap(other, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renombrar nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'Desde el menú');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(c.selectedNote?.title, 'Flutter');
      expect(
        repository.saved
            .singleWhere((note) => note.title == 'Desde el menú')
            .content,
        'Texto intacto',
      );

      final active = find.descendant(
        of: sidebar,
        matching: find.text('Flutter'),
      );
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text('Desde el menú')),
      );
      expect(c.selectedNote?.title, 'Desde el menú');

      await tester.tap(active);
      expect(c.selectedNote?.title, 'Flutter');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(active);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'Desde la barra');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(c.selectedNote?.title, 'Desde la barra');
      expect(find.byTooltip('Renombrar nota'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Preview toggles the exact task, including duplicate and nested labels',
    (tester) async {
      const source =
          '```md\n- [ ] Igual\n```\n\n- [ ] Igual\n  - [ ] Igual\n- [x] Igual\n\n> - [ ] Otra';
      final c = EditorNotifier(
        MemoryRepository(),
        recovered: EmptyRecoveredDrafts(),
      );
      await c.load();
      c.update(content: source);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final checks = find.byType(Checkbox);
      expect(checks, findsNWidgets(4));
      expect(
        tester
            .widgetList<Checkbox>(checks)
            .every((item) => item.onChanged != null),
        isTrue,
      );
      await tester.tap(checks.at(1));
      await tester.pumpAndSettle();
      expect(
        c.note.content,
        source.replaceFirst('  - [ ] Igual', '  - [x] Igual'),
      );
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Creates a note from a template and pastes a screenshot through Cmd+V',
    (tester) async {
      const clipboard = MethodChannel('folio/clipboard');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/NHEAAAAASUVORK5CYII=',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(clipboard, (_) async => png);
      addTearDown(() => messenger.setMockMethodCallHandler(clipboard, null));
      final repository = MemoryRepository();
      final c = EditorNotifier(repository, recovered: EmptyRecoveredDrafts());
      await c.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [editorProvider.overrideWithValue(c)],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton && widget.semanticLabel == 'Archivo',
        ),
      );
      await tester.pumpAndSettle();
      final templateAction = find.widgetWithText(
        PopupMenuItem<String>,
        'Nueva nota desde plantilla…',
      );
      expect(
        find.descendant(of: templateAction, matching: find.byType(Icon)),
        findsOneWidget,
      );
      await tester.tap(templateAction);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Idea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar plantilla'));
      await tester.pumpAndSettle();
      expect(c.note.title, 'Idea');
      expect(c.note.content, contains('## Primer experimento'));
      final editor = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.focusNode.debugLabel == 'Editor',
        ),
      );
      editor.controller.selection = TextSelection.collapsed(
        offset: c.note.content.length,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(
        c.note.content,
        contains('![Captura](${repository.images.keys.single})'),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsOneWidget,
      );
      messenger.setMockMethodCallHandler(clipboard, (_) async => null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return call.method == 'Clipboard.getData'
            ? {'text': 'Texto pegado'}
            : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.note.content, endsWith('Texto pegado'));
      await c.save();
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
      final c = EditorNotifier(
        MemoryRepository(),
        recovered: EmptyRecoveredDrafts(),
      );
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
