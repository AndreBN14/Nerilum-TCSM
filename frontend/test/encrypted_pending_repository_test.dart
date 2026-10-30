import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/repositories/encrypted_pending_analysis_repository.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'Los pendientes se cifran, persisten y se aíslan por propietario',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'nerilum_pending_test_',
      );
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      Future<Database> open(
        String path,
        String password,
        Future<void> Function(Database, int) create,
      ) => databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 1, onCreate: create),
      );
      EncryptedPendingAnalysisRepository repository() =>
          EncryptedPendingAnalysisRepository(
            rootOverride: folder,
            testKey: key,
            testDatabaseOpener: open,
          );

      final original = SelectedImage(
        name: 'scan.png',
        extension: 'png',
        bytes: Uint8List.fromList('PRIVATE MRI BYTES'.codeUnits),
      );
      final first = repository();
      final item = await first.enqueue('account-a', original);
      expect(await first.list('account-b'), isEmpty);
      await expectLater(first.image('account-b', item.id), throwsStateError);
      final encryptedFile = File(
        p.join(folder.path, 'nerilum_pending', '${item.id}.enc'),
      );
      final encrypted = await encryptedFile.readAsBytes();
      expect(encrypted, isNot(containsAllInOrder(original.bytes)));

      final reopened = repository();
      addTearDown(() async {
        await first.close();
        await reopened.close();
        await folder.delete(recursive: true);
      });
      expect((await reopened.list('account-a')).single.id, item.id);
      expect(
        (await reopened.image('account-a', item.id)).bytes,
        original.bytes,
      );
      await reopened.discard('account-a', item.id);
      expect(await reopened.list('account-a'), isEmpty);
      expect(await encryptedFile.exists(), isFalse);
    },
  );

  test('Detecta archivos alterados y limita pendientes por cuenta', () async {
    final folder = await Directory.systemTemp.createTemp(
      'nerilum_pending_limit_',
    );
    final repository = EncryptedPendingAnalysisRepository(
      rootOverride: folder,
      testKey: List<int>.filled(32, 7),
      testDatabaseOpener: (path, password, create) =>
          databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(version: 1, onCreate: create),
          ),
    );
    addTearDown(() async {
      await repository.close();
      await folder.delete(recursive: true);
    });
    final image = SelectedImage(
      name: 'mri.png',
      extension: 'png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final first = await repository.enqueue('owner', image);
    final file = File(
      p.join(folder.path, 'nerilum_pending', '${first.id}.enc'),
    );
    await file.writeAsBytes([0, 1, 2]);
    await expectLater(repository.image('owner', first.id), throwsStateError);
    for (var i = 1; i < 10; i++) {
      await repository.enqueue('owner', image);
    }
    await expectLater(repository.enqueue('owner', image), throwsStateError);
    expect((await repository.list('owner')).length, 10);
  });
}
