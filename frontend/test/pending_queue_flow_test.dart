import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/analysis_preview.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/pending_analysis.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/domain/repositories/pending_analysis_repository.dart';
import 'package:frontend/domain/repositories/preview_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Image implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'scan.png',
    extension: 'png',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

class _OfflineAnalysis implements AnalysisRepository, PreviewRepository {
  @override
  Future<AnalysisPreview> preview(SelectedImage image) async =>
      throw const AnalysisNetworkFailure('Sin conexión');
  @override
  Future<AnalysisResult> save(
    AnalysisPreview preview, {
    String? displayName,
  }) async => throw StateError('No guardar sin confirmación');
  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No usar legado');
  @override
  Future<List<AnalysisResult>> history() async => [];
}

class _Queue implements PendingAnalysisRepository {
  final items = <PendingAnalysis>[];
  @override
  Future<PendingAnalysis> enqueue(String ownerId, SelectedImage image) async {
    final item = PendingAnalysis(
      id: 'local-id',
      ownerId: ownerId,
      filename: image.name,
      extension: image.extension,
      createdAt: DateTime.utc(2026, 10, 29),
      status: 'pending',
    );
    items.add(item);
    return item;
  }

  @override
  Future<List<PendingAnalysis>> list(String ownerId) async =>
      items.where((item) => item.ownerId == ownerId).toList();
  @override
  Future<PendingAnalysis?> find(String ownerId, String id) async {
    for (final item in items) {
      if (item.ownerId == ownerId && item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> discard(String ownerId, String id) async =>
      items.removeWhere((item) => item.ownerId == ownerId && item.id == id);
  @override
  Future<SelectedImage> image(String ownerId, String id) =>
      throw UnimplementedError();
  @override
  Future<void> resetPreview(String ownerId, String id) async {}
  @override
  Future<void> releaseExpiredSave(String ownerId, String id) async {}
  @override
  Future<void> beginSave(
    String ownerId,
    String id, {
    required String previewId,
    required String proof,
    required DateTime expiresAt,
    required String name,
  }) async {}
  @override
  Future<void> complete(String ownerId, String id) async {}
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('Solo un fallo de red permite encolar y conserva el pendiente al cerrar sesión', () async {
    final queue = _Queue();
    final deps = AppDependencies(
      images: _Image(),
      analysis: _OfflineAnalysis(),
      pendingAnalyses: queue,
    );
    addTearDown(deps.dispose);
    await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
    final model = deps.mainViewModel;
    await model.pickImage();
    await model.analyze();
    expect(model.canQueueImage, isTrue);
    expect(queue.items, isEmpty);
    expect(await model.enqueueSelected(), isTrue);
    expect(model.image, isNull);
    expect(model.pendingAnalyses.single.ownerId, model.account!.id);
    expect(model.analyses, isEmpty);
    await model.logout();
    expect(model.pendingAnalyses, isEmpty);
    expect(queue.items, hasLength(1));
  });
}
