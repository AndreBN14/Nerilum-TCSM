import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Images implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'mri.png',
    extension: 'png',
    bytes: Uint8List.fromList([1]),
  );
}

class _RetryRepository implements AnalysisRepository {
  final keys = <String?>[];
  final names = <String?>[];

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    names.add(displayName);
    if (keys.length == 1) throw const AnalysisFailure('No se pudo conectar.');
    return AnalysisResult(
      id: 'an_1',
      category: 'NonDemented',
      createdAt: DateTime(2026),
      displayName: displayName,
    );
  }

  @override
  Future<List<AnalysisResult>> history() async =>
      throw const AnalysisFailure('No se pudo cargar el historial.');
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('Conserva clave al reintentar y la cambia para una nueva operación', () async {
    final repository = _RetryRepository();
    final deps = AppDependencies(images: _Images(), analysis: repository);
    addTearDown(deps.dispose);
    final model = deps.mainViewModel;
    await model.pickImage();
    model.setAnalysisName('Mi análisis');
    await model.analyze();
    expect(model.error, 'No se pudo conectar.');
    await model.analyze();
    expect(repository.keys[0], isNotNull);
    expect(repository.keys[0], repository.keys[1]);
    expect(repository.names, ['Mi análisis', 'Mi análisis']);
    expect(model.result?.id, 'an_1');
    expect(model.historyError, isNotNull);
    // Una pulsación después del éxito no debe reenviar la operación completada.
    await model.analyze();
    expect(repository.keys, hasLength(2));
    model.setAnalysisName('Otro análisis');
    await model.analyze();
    expect(repository.keys[2], isNot(repository.keys[1]));
    await model.pickImage();
    await model.analyze();
    expect(repository.keys[3], isNot(repository.keys[2]));
  });

  test(
    'El fallo de historial queda visible y finaliza el estado de carga',
    () async {
      final deps = AppDependencies(analysis: _RetryRepository());
      addTearDown(deps.dispose);
      await deps.mainViewModel.refreshHistory();
      expect(deps.mainViewModel.historyLoading, isFalse);
      expect(
        deps.mainViewModel.historyError,
        'No se pudo cargar el historial.',
      );
      expect(deps.mainViewModel.analyses, isEmpty);
    },
  );
}
