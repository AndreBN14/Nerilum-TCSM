import '../models/analysis_result.dart';
import '../models/selected_image.dart';

class AnalysisUnavailable implements Exception {
  const AnalysisUnavailable(this.message);
  final String message;
}

abstract class AnalysisRepository {
  Future<AnalysisResult> analyze(SelectedImage image);
  Future<List<AnalysisResult>> history();
}
