import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/theme.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_preview.dart';

void main() {
  testWidgets('Retro keeps the original and offers an optional ink print', (
    tester,
  ) async {
    // Dark screenshot background, two identical midtones, and white.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAABCAYAAAD5PA/NAAAAE0lEQVR4nGOQk5P7n5KSAsYgAAA/SgmsXjhZgQAAAABJRU5ErkJggg==',
    );
    final controller = ScrollController();
    final preview = MarkdownPreview(
      controller: controller,
      noteId: 'nota',
      content: '![Ejemplo](.folio-assets/ejemplo.png)',
      readImage: (_, _) async => png,
    );
    final inkPrint = find.byWidgetPredicate(
      (widget) =>
          widget is RawImage &&
          widget.filterQuality == FilterQuality.none &&
          widget.image != null,
    );
    addTearDown(controller.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.crema, AppStyle.retro),
          home: preview,
        ),
      );
      await tester.pump();
      expect(inkPrint, findsNothing);
      final initial = tester.widget<Image>(find.byType(Image));
      expect((initial.image as MemoryImage).bytes, same(png));

      await tester.tap(find.text('Tramado'));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 100 && inkPrint.evaluate().isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      final image = tester.widget<RawImage>(inkPrint).image!;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data!.buffer.asUint8List(), [
        41,
        42,
        34,
        255,
        41,
        42,
        34,
        255,
        247,
        241,
        226,
        255,
        247,
        241,
        226,
        255,
      ]);

      await tester.tap(find.byTooltip('Ampliar original'));
      await tester.pumpAndSettle();
      final zoomed = tester.widget<Image>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Image),
        ),
      );
      expect((zoomed.image as MemoryImage).bytes, same(png));
      await tester.tap(find.byTooltip('Cerrar imagen'));
      await tester.pumpAndSettle();
      expect(inkPrint, findsOneWidget);
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(inkPrint, findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.vivo, AppStyle.pop),
          themeAnimationDuration: Duration.zero,
          home: preview,
        ),
      );
      await tester.pump();
      expect(inkPrint, findsNothing);
      final original = tester.widget<Image>(find.byType(Image));
      expect((original.image as MemoryImage).bytes, same(png));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
