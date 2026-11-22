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
import 'package:folio/features/blog_publication/data/blog_connection.dart';
import 'package:folio/features/blog_publication/presentation/blog_publish_dialog.dart';
import 'package:folio/features/editor/data/file_repository.dart';
import 'package:folio/features/editor/domain/document_repository.dart';
import 'package:folio/features/editor/domain/markdown_document.dart';
import 'package:folio/features/editor/domain/notebook_snapshot.dart';
import 'package:folio/features/editor/domain/trashed_note.dart';
import 'package:folio/features/editor/data/recovered_drafts_repository.dart';
import 'package:folio/features/editor/presentation/controllers/editor_notifier.dart';
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
      expect(markdown.controller.offset, closeTo(120, 0.1));
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
      expect(tester.getTopLeft(find.text('EDITOR')).dx, before - 272);
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
    'The note ellipsis opens publication for that note without selecting it',
    (tester) async {
      final repository = MemoryRepository();
      await repository.createNote(title: 'Otra nota', content: 'Su borrador');
      final editor = EditorNotifier(
        repository,
        recovered: EmptyRecoveredDrafts(),
      );
      await editor.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorProvider.overrideWithValue(editor),
            blogConnectionProvider.overrideWith((ref) => null),
          ],
          child: const MyApp(home: EditorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Acciones de Otra nota'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publicar en arbe.blog…'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<BlogPublishDialog>(
        find.byType(BlogPublishDialog),
      );
      expect(dialog.noteTitle, 'Otra nota');
      expect(dialog.markdown, 'Su borrador');
      expect(editor.selectedNote?.title, 'Flutter');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
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
  testWidgets('Completes a portable note link and opens it in reading mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRepository()
      ..saved = const [
        MarkdownDocument(
          id: 'Daily/Inicio.md',
          title: 'Inicio',
          folder: 'Daily',
          content: '',
        ),
        MarkdownDocument(
          id: 'Work/Café #1.md',
          title: 'Café #1',
          folder: 'Work',
          content: 'Contenido del destino',
        ),
      ];
    final controller = EditorNotifier(
      repository,
      recovered: EmptyRecoveredDrafts(),
    );
    await controller.load();
    controller.select('Daily/Inicio.md');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [editorProvider.overrideWithValue(controller)],
        child: const MyApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final editor = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && widget.focusNode.debugLabel == 'Editor',
    );
    await tester.enterText(editor, '[[caf');
    await tester.pump();
    expect(find.text('Enlazar nota · ↑ ↓ · ↵'), findsOneWidget);
    expect(find.text('Contenido del destino'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.note.content, '[Café #1](<../Work/Caf%C3%A9%20%231.md>)');

    await tester.tap(find.byTooltip('Solo editor'));
    await tester.pumpAndSettle();
    expect(find.text('VISTA PREVIA'), findsNothing);
    await tester.tap(find.byTooltip('Solo vista previa'));
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    final link = find.text('Café #1', findRichText: true).last;
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(controller.selectedId, 'Work/Café #1.md');
    expect(find.text('VISTA PREVIA'), findsOneWidget);
    expect(editor, findsNothing);
    await tester.tap(find.byTooltip('Vista dividida'));
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);

    await controller.save();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await repository.events.close();
  });

  testWidgets('Renders code fence metadata in the preview', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEditorTheme(AppTheme.nord),
        home: Scaffold(
          body: MarkdownPreview(
            controller: scroll,
            content:
                '```ts filename="search.ts" title="Búsqueda" line=10\n'
                'const query = "café";\nreturn query;\n```',
          ),
        ),
      ),
    );
    expect(find.text('Búsqueda'), findsOneWidget);
    expect(find.text('search.ts · ts'), findsOneWidget);
    expect(find.text('10\n11'), findsOneWidget);
    expect(
      find.textContaining('return query;', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'Editor creates notes, navigates panes with keyboard, toggles tasks in view bar, and opens help',
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
      expect(find.text('Vim'), findsNothing);
      expect(find.byKey(const ValueKey('note-header-tasks-button')), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.focusNode.debugLabel == 'Editor',
        ),
        '# Flutter\n\nUn widget',
      );
      await tester.pumpAndSettle();
      expect(c.note.content, '# Flutter\n\nUn widget');

      // Navigate left to Sidebar with Ctrl+Left and back to Editor with Right Arrow
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Notas');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Editor');

      // Navigate right to Preview with Ctrl+Right and back to Editor with Left Arrow
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Vista previa');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Editor');

      // Clicking directly inside the editor must keep focus and allow typing
      final editorFinder = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.focusNode.debugLabel == 'Editor',
      );
      await tester.tap(editorFinder);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(editorFinder).focusNode.hasFocus,
        isTrue,
      );

      // Toggle Tasks panel from the note header view selector
      await tester.tap(find.byKey(const ValueKey('note-header-tasks-button')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byTooltip('Ocultar panel de tareas (⌘4 / ⌘⇧T)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('note-header-tasks-button')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byTooltip('Panel de tareas (⌘4 / ⌘⇧T)'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.notes.length, 2);

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
