import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/editor/data/file_repository.dart';
import 'package:folio/features/editor/data/notebook_sync_service.dart';

class WatchedFileRepository extends FileRepository {
  WatchedFileRepository({required super.directory});

  final events = StreamController<void>.broadcast();

  @override
  Stream<void> watch() => events.stream;

  void notifyFilesystemChange() => events.add(null);
}

void main() {
  test('coalesces file events into a Markdown snapshot', () async {
    final parent = await Directory.systemTemp.createTemp('folio-watch-');
    final repository = WatchedFileRepository(directory: parent);
    final service = NotebookSyncService(
      repository,
      debounce: const Duration(milliseconds: 15),
    );
    addTearDown(() async {
      await service.dispose();
      await repository.events.close();
      await parent.delete(recursive: true);
    });

    final updateFuture = service.updates.first.timeout(
      const Duration(seconds: 2),
    );
    service.start();
    await File('${parent.path}/Folio/External.md').create(recursive: true);
    await File('${parent.path}/Folio/External.md').writeAsString('changed');
    repository.notifyFilesystemChange();

    final update = await updateFuture;
    expect(update.error, isNull);
    expect(update.snapshot?.notes.single.id, 'External.md');
    expect(update.snapshot?.notes.single.content, 'changed');
  });
}
