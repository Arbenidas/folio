import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/blog_publication/data/blog_connection.dart';
import 'package:folio/features/blog_publication/data/blog_publication.dart';
import 'package:folio/features/blog_publication/presentation/blog_publish_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _capture = '.folio-assets/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
const _code = '.folio-assets/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+afo8AAAAASUVORK5CYII=';

void main() {
  testWidgets('review and cancel stay local until the author confirms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = _RecordingConnection();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blogConnectionProvider.overrideWith((ref) => connection)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BlogPublishDialog(
                  noteId: 'prueba.md',
                  noteTitle: 'Prueba',
                  markdown: '# Nota de prueba',
                  readImage: (_) async => null,
                ),
              ),
              child: const Text('Revisar artículo'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Revisar artículo'));
    await tester.pumpAndSettle();
    expect(find.text('Vista previa'), findsOneWidget);
    expect(connection.operations, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(connection.operations, isEmpty);

    tester.view.physicalSize = const Size(800, 620);
    await tester.tap(find.text('Revisar artículo'));
    await tester.pumpAndSettle();
    expect(find.text('Detalles'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Prueba editada');
    await tester.tap(find.text('Vista previa'));
    await tester.pumpAndSettle();
    expect(find.text('Prueba editada').hitTestable(), findsOneWidget);
    expect(find.text('Publicar ahora').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(find.text('https://arbe.blog/logs/prueba-editada'), findsOneWidget);
    expect(connection.operations, isEmpty);

    await tester.tap(find.text('Publicar ahora'));
    await tester.pumpAndSettle();
    expect(connection.operations, ['status', 'publish']);
    expect(connection.publishedBody?['title'], 'Prueba editada');
    expect(connection.publishedBody?['slug'], 'prueba-editada');
    expect(find.text('Artículo publicado'), findsOneWidget);
    expect(find.text('https://arbe.blog/logs/prueba'), findsOneWidget);
  });
  test(
    'prepares referenced captures once and ignores fenced examples',
    () async {
      final reads = <String>[];
      final captures = await prepareBlogCaptures(
        '![Pantalla][captura]\n\n![Repetida]($_capture)\n\n'
        '[captura]: $_capture\n\n'
        '```md\n![Ejemplo]($_code)\n```\n',
        (path) async {
          reads.add(path);
          return base64Decode(_png);
        },
      );

      expect(reads, [_capture]);
      expect(captures.single.alt, 'Pantalla');
      expect(captures.single.resized, isFalse);
    },
  );

  test(
    'reports missing and unsupported local images before publishing',
    () async {
      await expectLater(
        prepareBlogCaptures('![Pantalla]($_capture)', (_) async => null),
        throwsA(
          isA<BlogFailure>().having(
            (error) => error.message,
            'message',
            contains('Pantalla'),
          ),
        ),
      );
      await expectLater(
        prepareBlogCaptures(
          '![Otra](../otra.png)',
          (_) async => base64Decode(_png),
        ),
        throwsA(isA<BlogFailure>()),
      );
    },
  );

  test('publication retries identify the same snapshot and author', () {
    BlogPublication draft(String markdown) => BlogPublication(
      noteId: 'Notas/Prueba.md',
      markdown: markdown,
      title: 'Prueba',
      description: '',
      slug: blogSlug('Prueba'),
      category: BlogCategory.log,
      tags: const [],
      captures: const [],
    );

    final id = draft('# Prueba').requestId('autor A');
    expect(id, draft('# Prueba').requestId('autor A'));
    expect(id, isNot(draft('# Otra').requestId('autor A')));
    expect(id, isNot(draft('# Prueba').requestId('autor B')));
    expect(blogSlug('Una guía — del café'), 'una-guia-del-cafe');
  });

  test(
    'the banner goes with the article and shares an identical upload',
    () async {
      final connection = _RecordingConnection();
      final bytes = base64Decode(_png);
      final cover = BlogCover('banner.png', bytes);
      final article = BlogPublication(
        noteId: 'prueba.md',
        markdown: '![Captura]($_capture)',
        title: 'Prueba',
        description: '',
        slug: 'prueba',
        category: BlogCategory.log,
        tags: const ['folio'],
        captures: [BlogCapture(_capture, 'Captura', bytes, resized: false)],
        cover: cover,
      );

      await article.publish(connection, connection.session.user.id, (_) {});

      expect(connection.operations, ['status', 'upload', 'publish']);
      expect(connection.publishedBody?['cover_digest'], cover.digest);
      expect(connection.publishedBody?['tags'], ['folio']);
    },
  );
}

class _RecordingConnection implements BlogConnection {
  final operations = <String>[];
  Map<String, Object>? publishedBody;

  @override
  final keychainAvailable = const AlwaysStoppedAnimation(true);

  @override
  final Session session = Session(
    accessToken: 'fixture',
    tokenType: 'bearer',
    user: const User(
      id: 'autor',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    ),
  );

  @override
  Stream<AuthState> get authChanges => const Stream.empty();

  @override
  Future<Map<String, dynamic>> request(
    String operation,
    String authorId, {
    Object? body,
    Map<String, String> parameters = const {},
    String? contentType,
  }) async {
    operations.add(operation);
    if (operation == 'publish') publishedBody = body as Map<String, Object>;
    expect(authorId, session.user.id);
    return {
      'url': operation == 'publish' ? 'https://arbe.blog/logs/prueba' : null,
    };
  }

  @override
  Future<void> signIn(OAuthProvider provider) async {}

  @override
  Future<void> signOut() async {}
}
