import '../../domain/models/analysis_result.dart';

class AnalysisResultDto {
  static AnalysisResult fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final category = json['category'];
    final date = json['created_at'];
    final probability = json['probability'];
    final name = json['display_name'];
    final scores = json['scores'];
    if (id is! String ||
        id.isEmpty ||
        category is! String ||
        category.isEmpty ||
        date is! String ||
        probability is! num ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        (name != null && name is! String) ||
        scores is! Map<String, dynamic>) {
      throw const FormatException('Resultado de análisis no válido.');
    }
    final values = <String, double>{};
    for (final entry in scores.entries) {
      final score = entry.value;
      if (score is! num || !score.isFinite || score < 0 || score > 1) {
        throw const FormatException('Puntuaciones no válidas.');
      }
      values[entry.key] = score.toDouble();
    }
    if (!values.containsKey(category)) {
      throw const FormatException('Falta la categoría en las puntuaciones.');
    }
    return AnalysisResult(
      id: id,
      category: category,
      createdAt: DateTime.parse(date).toLocal(),
      displayName: name as String?,
      probability: probability.toDouble(),
      scores: Map.unmodifiable(values),
      isDemo: json['is_demo'] == true,
    );
  }
}
