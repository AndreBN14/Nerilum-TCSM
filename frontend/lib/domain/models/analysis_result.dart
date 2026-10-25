class AnalysisResult {
  const AnalysisResult({
    required this.category,
    required this.createdAt,
    this.displayName,
    this.probability,
    this.isDemo = false,
    this.scores = const {},
    this.id,
    this.modelName,
    this.modelVersion,
    this.modelDataset,
  });

  // La categoría debe corresponder exactamente a la etiqueta del modelo.
  final String category;
  final DateTime createdAt;
  // Nombre que la persona asigna al análisis; no es una conclusión clínica.
  final String? displayName;
  // Salida ilustrativa o puntuación del modelo entre 0 y 1, no probabilidad clínica.
  final double? probability;
  final bool isDemo;
  final Map<String, double> scores;
  final String? id;
  final String? modelName;
  final String? modelVersion;
  final String? modelDataset;
}
