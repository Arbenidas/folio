import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Keep reading notes and model output offline, even if Markdown contains a URL.
Widget localMarkdownImage(MarkdownImageConfig config) => Text(
  config.alt?.isNotEmpty == true ? '[Imagen: ${config.alt}]' : '[Imagen]',
  style: const TextStyle(fontStyle: FontStyle.italic),
);
