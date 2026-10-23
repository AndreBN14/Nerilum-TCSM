import '../models/analysis_result.dart';
import '../models/selected_image.dart';
import '../repositories/analysis_repository.dart';

class AnalyzeImage {
  const AnalyzeImage(this.repository);
  final AnalysisRepository repository;
  Future<AnalysisResult> call(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) => repository.analyze(
    image,
    displayName: displayName,
    idempotencyKey: idempotencyKey,
  );
}

class LoadHistory {
  const LoadHistory(this.repository);
  final AnalysisRepository repository;
  Future<List<AnalysisResult>> call() => repository.history();
}
