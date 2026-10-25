import 'analysis_result.dart';

class AnalysisPreview {
  const AnalysisPreview({
    required this.result,
    required this.saveProof,
    required this.expiresAt,
  });

  final AnalysisResult result;
  final String saveProof;
  final DateTime expiresAt;
}
