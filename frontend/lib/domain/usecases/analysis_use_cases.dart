import '../models/analysis_result.dart';
import '../models/selected_image.dart';
import '../repositories/analysis_repository.dart';

class AnalyzeImage {
  const AnalyzeImage(this.repository);
  final AnalysisRepository repository;
  Future<AnalysisResult> call(SelectedImage image) => repository.analyze(image);
}

class LoadHistory {
  const LoadHistory(this.repository);
  final AnalysisRepository repository;
  Future<List<AnalysisResult>> call() => repository.history();
}
