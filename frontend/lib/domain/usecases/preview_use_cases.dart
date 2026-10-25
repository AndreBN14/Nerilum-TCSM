import '../models/analysis_preview.dart';
import '../models/analysis_result.dart';
import '../models/selected_image.dart';
import '../repositories/preview_repository.dart';

class PreviewImage {
  const PreviewImage(this.repository);
  final PreviewRepository repository;
  Future<AnalysisPreview> call(SelectedImage image) =>
      repository.preview(image);
}

class SaveAnalysis {
  const SaveAnalysis(this.repository);
  final PreviewRepository repository;
  Future<AnalysisResult> call(AnalysisPreview preview, {String? displayName}) =>
      repository.save(preview, displayName: displayName);
}
