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
      throw const FormatException('Resultado no válido.');
    }
    final values = <String, double>{};
    for (final entry in scores.entries) {
      final value = entry.value;
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw const FormatException('Puntuaciones no válidas.');
      }
      values[entry.key] = value.toDouble();
    }
    if (!values.containsKey(category)) {
      throw const FormatException('Falta la categoría.');
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
