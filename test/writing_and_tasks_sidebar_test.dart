import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/theme.dart';
import 'package:folio/features/editor/data/note_exporter.dart';
import 'package:folio/features/editor/domain/markdown_document.dart';
import 'package:folio/features/editor/domain/note_template.dart';
import 'package:folio/features/editor/presentation/widgets/editor_motion.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_editing_assistant.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_source_controller.dart';
import 'package:folio/features/editor/presentation/widgets/note_inspector_panel.dart';
import 'package:folio/features/settings/presentation/views/settings_screen.dart';
import 'package:folio/features/tasks/data/task_repository.dart';
import 'package:folio/features/tasks/presentation/task_board_view.dart';
import 'package:folio/features/tasks/presentation/task_controller.dart';
import 'package:folio/main.dart';

void main() {
  testWidgets(
    'MarkdownSourceController preserves exact text 1:1 and caches spans',
    (tester) async {
      const sample = '''# Título principal
## Subtítulo

Texto con **negrita**, *cursiva*, ~~tachado~~, `código` y [enlace](https://folio.app).

- [ ] Pendiente
- [x] Completada
- Elemento de lista
> Una cita inspiradora

---

```dart
final x = 42;
```''';

      final controller = MarkdownSourceController()..text = sample;
      addTearDown(controller.dispose);

      TextSpan? firstSpan;
      TextSpan? secondSpan;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.papel),
          home: Builder(
            builder: (context) {
              const baseStyle = TextStyle(fontSize: 14.5);
              firstSpan = controller.buildTextSpan(
                context: context,
                style: baseStyle,
                withComposing: false,
              );
              secondSpan = controller.buildTextSpan(
                context: context,
                style: baseStyle,
                withComposing: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(firstSpan, isNotNull);
      expect(firstSpan!.toPlainText(), sample);
      expect(identical(firstSpan!.children, secondSpan!.children), isTrue);
    },
  );

  test('MarkdownEditingAssistant handles wrapping, tasks, and smart Enter', () {
    final controller = TextEditingController(text: 'Hola mundo')
      ..selection = const TextSelection(baseOffset: 5, extentOffset: 10);
    addTearDown(controller.dispose);

    MarkdownEditingAssistant.toggleWrap(controller, '**');
    expect(controller.text, 'Hola **mundo**');

    // Toggle again unwraps cleanly.
    MarkdownEditingAssistant.toggleWrap(controller, '**');
    expect(controller.text, 'Hola mundo');

    // Toggle task line cycles empty -> [ ] -> [x] -> plain.
    controller.selection = const TextSelection.collapsed(offset: 4);
    MarkdownEditingAssistant.toggleTaskLine(controller);
    expect(controller.text, '- [ ] Hola mundo');
    MarkdownEditingAssistant.toggleTaskLine(controller);
    expect(controller.text, '- [x] Hola mundo');
    MarkdownEditingAssistant.toggleTaskLine(controller);
    expect(controller.text, 'Hola mundo');

    // Smart Enter continues ordered lists and exits on empty marker.
    controller.value = const TextEditingValue(
      text: '1. Primer punto',
      selection: TextSelection.collapsed(offset: 15),
    );
    const enterEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    final handled = MarkdownEditingAssistant.handleKey(
      controller,
      enterEvent,
      isWriting: true,
    );
    expect(handled, KeyEventResult.handled);
    expect(controller.text, '1. Primer punto\n2. ');

    // Pressing Enter again on empty "2. " clears the marker.
    final exited = MarkdownEditingAssistant.handleKey(
      controller,
      enterEvent,
      isWriting: true,
    );
    expect(exited, KeyEventResult.handled);
    expect(controller.text, '1. Primer punto\n');
  });

  testWidgets(
    'TaskBoardView works in sidebar mode with Kanban, Eisenhower, and quick add',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('folio-tasks-test-');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final controller = TaskController(TaskRepository(dir));
      addTearDown(controller.dispose);
      await tester.runAsync(controller.load);

      const activeNote = MarkdownDocument(
        id: 'Ideas.md',
        title: 'Ideas',
        content: '# Ideas',
      );
      var expanded = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.crema),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: expanded ? 900 : 348,
                height: 700,
                child: TaskBoardView(
                  controller: controller,
                  notes: const [activeNote],
                  activeNote: activeNote,
                  isSidebar: !expanded,
                  onToggleExpand: () => setState(() => expanded = !expanded),
                  onOpenNote: (_) {},
                  onCreateNote: (_) {},
                  onBackToNotes: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TAREAS'), findsOneWidget);
      expect(find.text('Kanban'), findsOneWidget);
      expect(find.text('Eisenhower'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Hecha'), findsOneWidget);

      // Quick-add a task inline.
      await tester.enterText(
        find.byType(CupertinoTextField),
        'Pulir borrador',
      );
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.done);
      });
      await tester.pumpAndSettle();
      expect(find.text('Pulir borrador'), findsOneWidget);
      expect(controller.tasks.length, 1);

      // Switch to Eisenhower layout inside sidebar.
      await tester.tap(find.text('Eisenhower'));
      await tester.pumpAndSettle();
      expect(find.text('Hacer ya'), findsOneWidget);
      expect(find.text('Planificar'), findsOneWidget);
      expect(find.text('Delegar'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Más tarde'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Más tarde'), findsOneWidget);

      // Expand to full board mode.
      await tester.tap(find.bySemanticsLabel('Ampliar tablero'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Acoplar como barra lateral'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AnimatedRightPanel opens and closes smoothly without freezing and hosts live settings',
    (tester) async {
      final appearance = AppAppearance.instance;
      final originalTheme = appearance.selected;
      addTearDown(() => appearance.selected = originalTheme);

      var open = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MyApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Row(
                  children: [
                    const Expanded(child: Center(child: Text('LIVE EDITOR'))),
                    AnimatedRightPanel(
                      visible: open,
                      width: 360,
                      child: SettingsScreen(
                        embedded: true,
                        onClose: () => setState(() => open = false),
                        initialVolume: 0.5,
                        onVolumeChanged: (_) {},
                        initialNotesDirectory: Directory.systemTemp,
                        onNotesDirectoryChanged: (_) async {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Editor remains visible alongside live settings.
      expect(find.text('LIVE EDITOR'), findsOneWidget);
      expect(find.text('AJUSTES'), findsOneWidget);
      expect(find.text('En vivo'), findsOneWidget);

      // Switching theme updates live immediately.
      await tester.tap(find.text('Noche Cálida'));
      await tester.pumpAndSettle();
      expect(appearance.selected, AppTheme.noche);

      // Closing the right panel animates all the way down and unmounts.
      await tester.tap(find.bySemanticsLabel('Cerrar ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('AJUSTES'), findsNothing);
      expect(find.text('LIVE EDITOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'NoteMetadataExtractor extracts outline headings, tags, and backlinks accurately',
    () async {
      const target = MarkdownDocument(
        id: 'Folio.md',
        title: 'Folio',
        content: '# Folio\n\n#producto #macos\n\n## Arquitectura\n\n### Rendimiento\n',
      );
      const referrer = MarkdownDocument(
        id: 'Diario/2026-11-20.md',
        title: '2026-11-20',
        folder: 'Diario',
        content: '# Hoy\n\nTrabajando en [[Folio]] con #diario y #macos.\n',
      );

      final headings = NoteMetadataExtractor.extractHeadings(target.content);
      expect(headings.map((h) => (h.level, h.title)).toList(), [
        (1, 'Folio'),
        (2, 'Arquitectura'),
        (3, 'Rendimiento'),
      ]);

      final tags = NoteMetadataExtractor.extractTags(target.content);
      expect(tags, ['#macos', '#producto']);

      final backlinks = NoteMetadataExtractor.findBacklinks(target, [
        target,
        referrer,
      ]);
      expect(backlinks.single.note.id, referrer.id);

      final html = await NoteExporter.buildThemedHtml(
        title: target.title,
        noteId: target.id,
        markdown: target.content,
        colors: buildEditorTheme(AppTheme.papel).colorScheme,
        readImage: (_, _) async => null,
      );
      expect(html, contains('<h1>Folio</h1>'));
      expect(html, contains('Georgia'));
      expect(NoteTemplate.values.length, 9);
    },
  );
}
