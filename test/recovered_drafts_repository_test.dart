import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/editor/data/recovered_drafts_repository.dart';

void main() {
  test(
    'stores Markdown drafts privately and removes them when resolved',
    () async {
      final support = await Directory.systemTemp.createTemp('folio-recovery-');
      addTearDown(() => support.delete(recursive: true));
      final repository = RecoveredDraftsRepository(directory: support);

      final saved = await repository.save(
        title: 'Nota original',
        content: '# Borrador',
      );
      final drafts = await repository.list();

      expect(drafts, hasLength(1));
      expect(drafts.single.id, saved.id);
      expect(drafts.single.title, contains('Nota original'));
      expect(drafts.single.content, '# Borrador');
      expect(saved.id, startsWith('${support.path}/Folio/Recovered drafts/'));
      expect(saved.id, endsWith('.md'));

      await repository.delete(saved.id);
      expect(await repository.list(), isEmpty);
    },
  );
}
