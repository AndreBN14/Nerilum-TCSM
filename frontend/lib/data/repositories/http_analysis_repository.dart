import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../datasources/http_analysis_data_source.dart';

class HttpAnalysisRepository implements AnalysisRepository {
  const HttpAnalysisRepository(this.source);
  final HttpAnalysisDataSource source;
  @override
  Future<AnalysisResult> analyze(SelectedImage image, {String? displayName}) =>
      source.analyze(image, displayName: displayName);
  @override
  Future<List<AnalysisResult>> history() => source.history();
}
