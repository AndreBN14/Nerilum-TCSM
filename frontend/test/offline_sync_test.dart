import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/data/repositories/encrypted_pending_analysis_repository.dart';
import 'package:frontend/domain/models/analysis_preview.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/domain/repositories/preview_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Image implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'scan.png',
    extension: 'png',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

class _Remote
    implements AnalysisRepository, PreviewRepository, AnalysisLookupRepository {
  bool disconnected = true;
  bool dropFirstSaveResponse = false;
  int previewCalls = 0;
  int saveCalls = 0;
  AnalysisResult? stored;

  @override
  Future<AnalysisPreview> preview(SelectedImage image) async {
    if (disconnected) throw const AnalysisNetworkFailure('Sin conexión');
    previewCalls++;
    return AnalysisPreview(
      result: AnalysisResult(
        id: 'an_123abc',
        category: 'NonDemented',
        probability: .8,
        scores: const {'NonDemented': .8},
        createdAt: DateTime.now().toUtc(),
      ),
      saveProof: 'comprobante-firmado',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }

  @override
  Future<AnalysisResult> save(
    AnalysisPreview preview, {
    String? displayName,
  }) async {
    saveCalls++;
    stored ??= AnalysisResult(
      id: preview.result.id,
      category: 'NonDemented',
      createdAt: DateTime.now().toUtc(),
      displayName: displayName,
      probability: .8,
      scores: const {'NonDemented': .8},
    );
    if (dropFirstSaveResponse) {
      dropFirstSaveResponse = false;
      throw const AnalysisNetworkFailure('Respuesta perdida');
    }
    return stored!;
  }

  @override
  Future<AnalysisResult?> findById(String id) async =>
      stored?.id == id ? stored : null;
  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No usar endpoint legado');
  @override
  Future<List<AnalysisResult>> history() async =>
      stored == null ? [] : [stored!];
}

void main() {
  sqfliteFfiInit();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test(
    'Encolar, previsualizar y salir conserva pendiente sin guardarlo',
    () async {
      final dir = await Directory.systemTemp.createTemp('nerilum_sync_');
      final queue = EncryptedPendingAnalysisRepository(
        rootOverride: dir,
        testKey: List<int>.filled(32, 7),
        testDatabaseOpener: (path, password, create) =>
            databaseFactoryFfi.openDatabase(
              path,
              options: OpenDatabaseOptions(version: 1, onCreate: create),
            ),
      );
      addTearDown(() async {
        await queue.close();
        await dir.delete(recursive: true);
      });
      final remote = _Remote();
      final deps = AppDependencies(
        images: _Image(),
        analysis: remote,
        pendingAnalyses: queue,
      );
      addTearDown(deps.dispose);
      await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
      final model = deps.mainViewModel;
      await model.pickImage();
      await model.analyze();
      expect(await model.enqueueSelected(), isTrue);
      final pending = model.pendingAnalyses.single;
      remote.disconnected = false;
      expect(await model.previewPending(pending.id), isTrue);
      expect(remote.stored, isNull);
      model.discardPreview();
      expect((await queue.list(pending.ownerId)).single.id, pending.id);
      expect(await model.previewPending(pending.id), isTrue);
      expect(remote.previewCalls, 2);
      expect(remote.stored, isNull);
      model.setAnalysisName('Control');
      await model.savePreview();
      expect(model.result?.displayName, 'Control');
      expect(remote.saveCalls, 1);
      expect(await queue.list(pending.ownerId), isEmpty);
    },
  );

  test('Respuesta perdida: el mismo comprobante se recupera tras reiniciar sin duplicados', () async {
    final dir = await Directory.systemTemp.createTemp('nerilum_recovery_');
    final queue = EncryptedPendingAnalysisRepository(
      rootOverride: dir,
      testKey: List<int>.filled(32, 8),
      testDatabaseOpener: (path, password, create) =>
          databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(version: 1, onCreate: create),
          ),
    );
    addTearDown(() async {
      await queue.close();
      await dir.delete(recursive: true);
    });
    final remote = _Remote();
    final first = AppDependencies(
      images: _Image(),
      analysis: remote,
      pendingAnalyses: queue,
    );
    await first.accountRepository.login('demo@nerilum.app', 'Demo1234');
    final model = first.mainViewModel;
    await model.pickImage();
    await model.analyze();
    await model.enqueueSelected();
    final pending = model.pendingAnalyses.single;
    remote.disconnected = false;
    await model.previewPending(pending.id);
    model.setAnalysisName('Control');
    remote.dropFirstSaveResponse = true;
    await model.savePreview();
    expect(model.preview, isNotNull);
    expect((await queue.find(pending.ownerId, pending.id))!.status, 'saving');
    model.setAnalysisName('Otro');
    expect(model.analysisName, 'Control');
    first.dispose();

    final reopened = AppDependencies(
      images: _Image(),
      analysis: remote,
      pendingAnalyses: queue,
    );
    addTearDown(reopened.dispose);
    await reopened.restoreLocalState();
    final recovered = await reopened.mainViewModel.resumePendingSave(
      pending.id,
    );
    expect(recovered?.displayName, 'Control');
    expect(remote.saveCalls, 1);
    expect(await queue.list(pending.ownerId), isEmpty);
  });

  test(
    'Comprobante caducado sin registro remoto vuelve a pendiente sin guardar',
    () async {
      final dir = await Directory.systemTemp.createTemp('nerilum_expiry_');
      final queue = EncryptedPendingAnalysisRepository(
        rootOverride: dir,
        testKey: List<int>.filled(32, 9),
        testDatabaseOpener: (path, password, create) =>
            databaseFactoryFfi.openDatabase(
              path,
              options: OpenDatabaseOptions(version: 1, onCreate: create),
            ),
      );
      addTearDown(() async {
        await queue.close();
        await dir.delete(recursive: true);
      });
      final remote = _Remote()..disconnected = false;
      final deps = AppDependencies(analysis: remote, pendingAnalyses: queue);
      addTearDown(deps.dispose);
      await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
      final owner = deps.accountRepository.currentAccount!.id;
      final item = await queue.enqueue(
        owner,
        SelectedImage(
          name: 'mri.png',
          extension: 'png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      await queue.beginSave(
        owner,
        item.id,
        previewId: 'an_abc123',
        proof: 'proof',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        name: 'Control',
      );
      expect(await deps.mainViewModel.resumePendingSave(item.id), isNull);
      expect((await queue.find(owner, item.id))?.status, 'pending');
      expect(remote.saveCalls, 0);
      expect(deps.mainViewModel.pendingError, contains('expiró'));
      expect((await queue.image(owner, item.id)).bytes, [1, 2, 3]);
    },
  );
}
