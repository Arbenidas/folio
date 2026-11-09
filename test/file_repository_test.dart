import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/editor/data/file_repository.dart';

void main() {
  late Directory parent;
  late FileRepository repository;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('folio-markdown-');
    repository = FileRepository(directory: parent);
  });

  tearDown(() async {
    if (await parent.exists()) await parent.delete(recursive: true);
  });

  test('uses a real Folio tree and plain Markdown files', () async {
    await repository.createFolder('Ideas/Empty');
    final note = await repository.createNote(
      title: 'Draft',
      folder: 'Ideas',
      content: '# Markdown\n\nBody only.',
    );

    expect(note.id, 'Ideas/Draft.md');
    expect(
      await File('${parent.path}/Folio/Ideas/Draft.md').readAsString(),
      '# Markdown\n\nBody only.',
    );
    final snapshot = await repository.load();
    expect(snapshot.folderPaths, containsAll(['Ideas', 'Ideas/Empty']));
    expect(snapshot.notes.single.content, '# Markdown\n\nBody only.');
  });

  test(
    'allows same titles in separate folders and suffixes local collisions',
    () async {
      final first = await repository.createNote(title: 'Idea', folder: 'A');
      final second = await repository.createNote(title: 'Idea', folder: 'B');
      final duplicate = await repository.createNote(title: 'Idea', folder: 'A');

      expect(first.id, 'A/Idea.md');
      expect(second.id, 'B/Idea.md');
      expect(duplicate.id, 'A/Idea 2.md');
    },
  );

  test(
    'folder rename updates note paths and delete rehomes its contents',
    () async {
      await repository.createNote(
        title: 'Note',
        folder: 'Old/Nested',
        content: 'body',
      );
      await repository.createFolder('Old/Empty');

      await repository.renameFolder('Old', 'New');
      var snapshot = await repository.scan();
      expect(snapshot.notes.single.id, 'New/Nested/Note.md');
      expect(snapshot.folderPaths, contains('New/Empty'));

      await repository.deleteFolder('New');
      snapshot = await repository.scan();
      expect(snapshot.notes.single.id, 'Nested/Note.md');
      expect(snapshot.folderPaths, contains('Nested'));
      expect(snapshot.folderPaths, isNot(contains('New')));
    },
  );

  test('external Markdown edits appear on the next scan', () async {
    await repository.createNote(title: 'Outside', content: 'before');
    await File('${parent.path}/Folio/Outside.md').writeAsString('after');

    expect((await repository.scan()).notes.single.content, 'after');
  });

  test('images survive moves, trash restoration and notebook copies', () async {
    final destination = await Directory.systemTemp.createTemp('folio-copy-');
    addTearDown(() => destination.delete(recursive: true));
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/NHEAAAAASUVORK5CYII=',
    );
    final note = await repository.createNote(title: 'Imagen', folder: 'A');
    final reference = await repository.saveImage(note.id, png);
    await repository.saveNote(note.copyWith(content: '![Captura]($reference)'));

    final moved = await repository.moveNote(note.id, 'B');
    expect(await repository.readImage(moved.id, reference), png);
    await repository.deleteNote(moved.id);
    expect((await repository.scan()).notes, isEmpty);
    await repository.createNote(
      title: 'Imagen',
      folder: 'B',
      content: 'Otra nota',
    );
    final entry = (await repository.listTrash()).single;
    expect(entry.folder, 'B');
    final copied = await FileRepository.copyNotebookInto(
      destination,
      await repository.scan(),
      sourceRepository: repository,
    );
    expect(copied.notes.single.content, 'Otra nota');
    final restored = await repository.restoreDeletedNote(entry.id);
    expect(restored.id, 'B/Imagen 2.md');
    expect(await repository.readImage(restored.id, reference), png);
    expect(await repository.listTrash(), isEmpty);

    final target = FileRepository(directory: destination);
    final targetRestored = await target.restoreDeletedNote(
      (await target.listTrash()).single.id,
    );
    expect(await target.readImage(targetRestored.id, reference), png);
    expect(await target.readImage(targetRestored.id, '../$reference'), isNull);
  });
}
