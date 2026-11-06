import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/analysis_preview.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/domain/repositories/preview_repository.dart';

class _ImageRepo implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'scan.png',
    extension: 'png',
    bytes: Uint8List.fromList([1, 2]),
  );
}

class _PreviewRepo implements AnalysisRepository, PreviewRepository {
  int previewCalls = 0;
  int saveCalls = 0;
  int historyCalls = 0;
  bool failSave = false;

  @override
  Future<AnalysisPreview> preview(SelectedImage image) async {
    previewCalls++;
    return AnalysisPreview(
      result: AnalysisResult(
        id: 'an_123',
        category: 'NonDemented',
        createdAt: DateTime.utc(2026, 10, 24),
        probability: .8,
        scores: const {'NonDemented': .8},
      ),
      saveProof: 'proof',
      expiresAt: DateTime.utc(2026, 10, 24, 1),
    );
  }

  @override
  Future<AnalysisResult> save(
    AnalysisPreview preview,
    SelectedImage image, {
    String? displayName,
  }) async {
    saveCalls++;
    expect(image.bytes, orderedEquals([1, 2]));
    if (failSave) throw const AnalysisFailure('Error temporal.');
    return AnalysisResult(
      id: preview.result.id,
      category: preview.result.category,
      createdAt: preview.result.createdAt,
      probability: preview.result.probability,
      scores: preview.result.scores,
      displayName: displayName,
    );
  }

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No usar ruta legacy');

  @override
  Future<List<AnalysisResult>> history() async {
    historyCalls++;
    return const [];
  }
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test(
    'Solo guarda tras decisión; editar nombre no vuelve a inferir',
    () async {
      final repo = _PreviewRepo();
      final deps = AppDependencies(images: _ImageRepo(), analysis: repo);
      addTearDown(deps.dispose);
      final model = deps.mainViewModel;
      await model.pickImage();
      await model.analyze();
      expect(model.preview, isNotNull);
      expect(model.result, isNull);
      expect(repo.previewCalls, 1);
      expect(repo.historyCalls, 0);
      model.setAnalysisName('  Control  ');
      expect(repo.previewCalls, 1);
      repo.failSave = true;
      await model.savePreview();
      expect(model.preview, isNotNull);
      expect(repo.saveCalls, 1);
      repo.failSave = false;
      await model.savePreview();
      expect(model.preview, isNull);
      expect(model.result?.displayName, 'Control');
      expect(repo.previewCalls, 1);
      expect(repo.saveCalls, 2);
      expect(repo.historyCalls, 1);
      expect(model.imageForRecord('an_123'), orderedEquals([1, 2]));
    },
  );

  test(
    'Descartar y cerrar sesión limpian la previsualización y la imagen',
    () async {
      final repo = _PreviewRepo();
      final deps = AppDependencies(images: _ImageRepo(), analysis: repo);
      addTearDown(deps.dispose);
      final model = deps.mainViewModel;
      await model.pickImage();
      await model.analyze();
      model.discardPreview();
      expect(model.preview, isNull);
      expect(repo.saveCalls, 0);
      await model.analyze();
      await model.savePreview();
      model.clearSessionState();
      expect(model.imageForRecord('an_123'), isNull);
      expect(model.result, isNull);
    },
  );
}
