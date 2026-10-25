import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/preview_repository.dart';
import '../../domain/models/analysis_preview.dart';
import '../datasources/http_analysis_data_source.dart';

class HttpAnalysisRepository implements AnalysisRepository, PreviewRepository {
  const HttpAnalysisRepository(this.source);
  final HttpAnalysisDataSource source;

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) => source.analyze(
    image,
    displayName: displayName,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<List<AnalysisResult>> history() => source.history();

  @override
  Future<AnalysisPreview> preview(SelectedImage image) => source.preview(image);

  @override
  Future<AnalysisResult> save(AnalysisPreview preview, {String? displayName}) =>
      source.savePreview(preview, displayName: displayName);
}

class UnconfiguredAnalysisRepository implements AnalysisRepository {
  const UnconfiguredAnalysisRepository();

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw const AnalysisUnavailable(
    'El backend de análisis aún no está configurado para esta versión de la app.',
  );

  @override
  Future<List<AnalysisResult>> history() async => const [];
}
