import '../models/analysis_result.dart';
import '../models/selected_image.dart';

class AnalysisUnavailable implements Exception {
  const AnalysisUnavailable(this.message);
  final String message;
}

class AnalysisFailure implements Exception {
  const AnalysisFailure(this.message);
  final String message;
}

class AnalysisNetworkFailure extends AnalysisFailure {
  const AnalysisNetworkFailure(super.message);
}

class AnalysisNotFound extends AnalysisFailure {
  const AnalysisNotFound() : super('Análisis no encontrado.');
}

abstract class AnalysisRepository {
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  });
  Future<List<AnalysisResult>> history();
}

abstract class AnalysisLookupRepository {
  Future<AnalysisResult?> findById(String id);
}
