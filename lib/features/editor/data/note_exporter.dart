import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../domain/markdown_document.dart';

/// Exports a note as a self-contained themed HTML or print-ready PDF using the
/// active Folio color palette and editorial typography.
abstract final class NoteExporter {
  static const _channel = MethodChannel('folio/export');

  static Future<String?> exportHtml({
    required MarkdownDocument note,
    required String content,
    required ColorScheme colors,
    required Future<Uint8List?> Function(String noteId, String reference)
    readImage,
  }) async {
    final html = await buildThemedHtml(
      title: note.title,
      noteId: note.id,
      markdown: content,
      colors: colors,
      readImage: readImage,
    );
    final fileName = '${_safeFileName(note.title)}.html';
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Exportar como HTML',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['html'],
      bytes: Uint8List.fromList(utf8.encode(html)),
    );
    if (savedUri == null) return null;
    return savedUri.path.isEmpty ? fileName : savedUri.path;
  }

  static Future<String?> exportPdf({
    required MarkdownDocument note,
    required String content,
    required ColorScheme colors,
    required Future<Uint8List?> Function(String noteId, String reference)
    readImage,
  }) async {
    final html = await buildThemedHtml(
      title: note.title,
      noteId: note.id,
      markdown: content,
      colors: colors,
      readImage: readImage,
      forPdf: true,
    );
    final pdfBytes = await _channel.invokeMethod<Uint8List>('renderPdf', html);
    if (pdfBytes == null || pdfBytes.isEmpty) {
      throw const FileSystemException('No se pudo generar el archivo PDF.');
    }
    final fileName = '${_safeFileName(note.title)}.pdf';
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Exportar como PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: pdfBytes,
    );
    if (savedUri == null) return null;
    return savedUri.path.isEmpty ? fileName : savedUri.path;
  }

  static Future<String> buildThemedHtml({
    required String title,
    required String noteId,
    required String markdown,
    required ColorScheme colors,
    required Future<Uint8List?> Function(String noteId, String reference)
    readImage,
    bool forPdf = false,
  }) async {
    var bodyHtml = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );

    // Inline local .folio-assets/ images as data URIs so HTML/PDF is portable.
    final imgPattern = RegExp(r'src="(\.folio-assets/[^"]+)"');
    final matches = imgPattern.allMatches(bodyHtml).toList();
    for (final match in matches.reversed) {
      final ref = match.group(1)!;
      final bytes = await readImage(noteId, ref);
      if (bytes == null) continue;
      final encoded = base64Encode(bytes);
      bodyHtml = bodyHtml.replaceRange(
        match.start,
        match.end,
        'src="data:image/png;base64,$encoded"',
      );
    }

    final bg = _cssHex(colors.surfaceContainerLowest);
    final pageBg = _cssHex(colors.surface);
    final fg = _cssHex(colors.onSurface);
    final muted = _cssHex(colors.onSurfaceVariant);
    final primary = _cssHex(colors.primary);
    final codeBg = _cssHex(colors.surfaceContainerLow);
    final inlineCodeBg = _cssHex(colors.surfaceContainerHigh);
    final border = _cssHex(colors.outlineVariant);

    final escapedTitle = const HtmlEscape().convert(title);

    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$escapedTitle</title>
  <style>
    :root {
      color-scheme: ${colors.brightness == Brightness.dark ? 'dark' : 'light'};
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: ${forPdf ? bg : pageBg};
      color: $fg;
      font-family: Georgia, "New York", "Iowan Old Style", serif;
      font-size: 16px;
      line-height: 1.78;
      -webkit-font-smoothing: antialiased;
    }
    main {
      max-width: 720px;
      margin: ${forPdf ? '0 auto' : '44px auto'};
      padding: ${forPdf ? '36px 44px' : '44px 52px'};
      background: $bg;
      ${forPdf ? '' : 'border: 1px solid $border; border-radius: 14px;'}
    }
    h1, h2, h3, h4 {
      color: $fg;
      line-height: 1.3;
      margin-top: 1.6em;
      margin-bottom: 0.55em;
      font-weight: 700;
    }
    h1 { font-size: 2rem; margin-top: 0; letter-spacing: -0.02em; }
    h2 { font-size: 1.45rem; border-bottom: 1px solid $border; padding-bottom: 0.25em; }
    h3 { font-size: 1.18rem; }
    p { margin: 0 0 1.05em; }
    a { color: $primary; text-decoration: underline; text-underline-offset: 3px; }
    code {
      font-family: Menlo, "SF Mono", ui-monospace, monospace;
      font-size: 0.84em;
      background: $inlineCodeBg;
      padding: 0.14em 0.42em;
      border-radius: 5px;
    }
    pre {
      background: $codeBg;
      border: 1px solid $border;
      border-radius: 10px;
      padding: 14px 16px;
      overflow-x: auto;
      line-height: 1.6;
    }
    pre code {
      background: transparent;
      padding: 0;
      font-size: 0.82em;
    }
    blockquote {
      margin: 1.2em 0;
      padding: 10px 18px;
      border-left: 3.5px solid $primary;
      background: $codeBg;
      border-radius: 0 8px 8px 0;
      color: $muted;
      font-style: italic;
    }
    hr {
      border: 0;
      border-top: 1px solid $border;
      margin: 2em 0;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
      margin: 0.8em 0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 1.2em 0;
      font-size: 0.92em;
    }
    th, td {
      border: 1px solid $border;
      padding: 8px 12px;
      text-align: left;
    }
    th { background: $codeBg; font-weight: 700; }
    ul, ol { padding-left: 1.5em; margin: 0 0 1em; }
    li { margin-bottom: 0.35em; }
    input[type="checkbox"] { accent-color: $primary; margin-right: 6px; }
    @media print {
      body { background: $bg; }
      main { margin: 0; border: none; border-radius: 0; }
    }
  </style>
</head>
<body>
  <main>
    $bodyHtml
  </main>
</body>
</html>
''';
  }

  static String _safeFileName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? 'Nota de Folio' : cleaned;
  }

  static String _cssHex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
}
