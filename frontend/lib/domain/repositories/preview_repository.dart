import '../models/analysis_preview.dart';
import '../models/analysis_result.dart';
import '../models/selected_image.dart';

abstract class PreviewRepository {
  Future<AnalysisPreview> preview(SelectedImage image);
  Future<AnalysisResult> save(
    AnalysisPreview preview,
    SelectedImage image, {
    String? displayName,
  });
  Future<AnalysisResult> saveWithoutImage(
    AnalysisPreview preview, {
    String? displayName,
  });
}
