import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:markdown/markdown.dart' as md;

import 'blog_connection.dart';

enum BlogCategory {
  log('Bitácora', 'logs'),
  guide('Guía', 'guides'),
  work('Proyecto', 'works');

  const BlogCategory(this.label, this.path);
  final String label;
  final String path;
}

String blogSlug(String title) {
  final lower = title.toLowerCase();
  final latin = lower
      .replaceAll(RegExp('[áàâäãå]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôöõ]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');
  final slug = latin
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'[\s-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 80
      ? slug.substring(0, 80).replaceFirst(RegExp(r'-+$'), '')
      : slug;
}

final _capturePath = RegExp(r'^\.folio-assets/[a-f0-9]{32}\.png$');
final _validSlug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
const _maxPng = 5 * 1024 * 1024;
const _pngSignature = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
];

class BlogCapture {
  BlogCapture(this.path, this.alt, this.bytes, {required this.resized});
  final String path;
  final String alt;
  final Uint8List bytes;
  final bool resized;
  late final String digest = sha256.convert(bytes).toString();
}

class BlogCover {
  BlogCover(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  late final String digest = sha256.convert(bytes).toString();
}

Future<BlogCover?> pickBlogCover() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  if (file == null) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    if (bytes.length + chunk.length > 20 * 1024 * 1024) {
      throw const BlogFailure('Elige un banner de hasta 20 MiB.');
    }
    bytes.add(chunk);
  }
  final png = await _fitPng(bytes.takeBytes());
  if (png == null) {
    throw const BlogFailure(
      'No se pudo preparar el banner. Prueba con otra imagen.',
    );
  }
  return BlogCover(file.name, png);
}

Future<List<BlogCapture>> prepareBlogCaptures(
  String markdown,
  Future<Uint8List?> Function(String path) read,
) async {
  final images = <String, String>{};
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'img') {
      final src = node.attributes['src'] ?? '';
      final uri = Uri.tryParse(src);
      if (_capturePath.hasMatch(src)) {
        images.putIfAbsent(src, () => node.attributes['alt'] ?? '');
      } else if (uri?.scheme != 'https' || uri?.host.isEmpty != false) {
        throw const BlogFailure(
          'Usa capturas pegadas en Folio o imágenes con una URL HTTPS.',
        );
      }
    }
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child);
    }
  }

  for (final node in md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(const LineSplitter().convert(markdown))) {
    visit(node);
  }
  if (images.length > 12) {
    throw const BlogFailure('Puedes enviar hasta 12 capturas por artículo.');
  }
  final captures = <BlogCapture>[];
  for (final entry in images.entries) {
    final bytes = await read(entry.key);
    final name = entry.value.isEmpty
        ? 'Captura ${captures.length + 1}'
        : entry.value;
    if (bytes == null) throw BlogFailure('No se encontró «$name».');
    if (bytes.length < 45 ||
        List.generate(
          _pngSignature.length,
          (index) => index,
        ).any((index) => bytes[index] != _pngSignature[index])) {
      throw BlogFailure('«$name» no es una captura PNG válida.');
    }
    if (bytes.length <= _maxPng) {
      captures.add(BlogCapture(entry.key, name, bytes, resized: false));
    } else {
      final reduced = await _fitPng(bytes);
      if (reduced == null) {
        throw BlogFailure('No se pudo reducir «$name» a 5 MiB.');
      }
      captures.add(BlogCapture(entry.key, name, reduced, resized: true));
    }
  }
  return captures;
}

Future<Uint8List?> _fitPng(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      final longest = width > height ? width : height;
      if (width * height > 80000000) return null;
      for (final limit in {
        if (longest < 2400) longest,
        2400,
        1800,
        1200,
        800,
      }) {
        if (longest < limit) continue;
        final codec = await descriptor.instantiateCodec(
          targetWidth: (width * limit / longest).round().clamp(1, limit),
          targetHeight: (height * limit / longest).round().clamp(1, limit),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (data != null && data.lengthInBytes <= _maxPng) {
              return data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
  return null;
}

class BlogPublication {
  BlogPublication({
    required this.noteId,
    required this.markdown,
    required this.title,
    required this.description,
    required this.slug,
    required this.category,
    required this.tags,
    required this.captures,
    this.cover,
  });

  final String noteId;
  final String markdown;
  final String title;
  final String description;
  final String slug;
  final BlogCategory category;
  final List<String> tags;
  final List<BlogCapture> captures;
  final BlogCover? cover;

  Uri get previewUrl => blogSite.replace(pathSegments: [category.path, slug]);

  Map<String, Object> get _payload => {
    'title': title,
    'description': description,
    'slug': slug,
    'category': category.name,
    'tags': tags,
    'markdown': markdown,
    'images': {for (final capture in captures) capture.path: capture.digest},
    'cover_digest': ?cover?.digest,
  };

  // The same author and snapshot can safely retry even after reopening Folio.
  String requestId(String authorId) {
    final hex = sha256
        .convert(
          utf8.encode(
            jsonEncode(['folio-publication-v1', authorId, noteId, _payload]),
          ),
        )
        .toString();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-8${hex.substring(13, 16)}-8${hex.substring(17, 20)}-${hex.substring(20, 32)}';
  }

  void validate() {
    if (title.isEmpty ||
        title.length > 160 ||
        description.length > 320 ||
        markdown.trim().isEmpty ||
        utf8.encode(markdown).length > 1024 * 1024 ||
        tags.length > 12 ||
        tags.any((tag) => tag.length > 40)) {
      throw const BlogFailure(
        'Revisa el título, el resumen, el texto y las palabras clave del artículo.',
      );
    }
    if (slug.length > 80 ||
        !_validSlug.hasMatch(slug) ||
        const {'preview', 'system-settings'}.contains(slug)) {
      throw const BlogFailure(
        'Usa una URL de hasta 80 caracteres con letras minúsculas, números y guiones.',
      );
    }
  }

  Future<Uri> publish(
    BlogConnection connection,
    String authorId,
    void Function(String) progress,
  ) async {
    validate();
    final id = requestId(authorId);
    final attempt = await connection.request(
      'status',
      authorId,
      parameters: {'request_id': id},
    );
    if (attempt['url'] != null) return _resultUrl(attempt);
    final uploaded = <String>{};
    Future<void> upload(String digest, Uint8List bytes) async {
      if (!uploaded.add(digest)) return;
      await connection.request(
        'upload',
        authorId,
        parameters: {'request_id': id, 'digest': digest},
        contentType: 'image/png',
        body: bytes,
      );
    }

    if (cover case final banner?) {
      progress('Subiendo banner…');
      await upload(banner.digest, banner.bytes);
    }
    for (var index = 0; index < captures.length; index++) {
      progress('Subiendo captura ${index + 1} de ${captures.length}…');
      final capture = captures[index];
      await upload(capture.digest, capture.bytes);
    }
    progress('Publicando artículo…');
    final result = await connection.request(
      'publish',
      authorId,
      body: {'request_id': id, ..._payload},
    );
    return _resultUrl(result);
  }

  Uri _resultUrl(Map<String, dynamic> response) {
    final raw = response['url'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null ||
        !uri.hasAuthority ||
        uri.origin != blogSite.origin ||
        uri.userInfo.isNotEmpty) {
      throw const BlogFailure('arbe.blog no devolvió un enlace válido.');
    }
    return uri;
  }
}
