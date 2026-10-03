import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/analysis_repository.dart';

// Los registros demo son ilustrativos; nunca provienen de inferencia real.
class MockAnalysisDataSource {
  const MockAnalysisDataSource();

  Future<AnalysisResult> analyze(SelectedImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    throw const AnalysisUnavailable(
      'El modelo de clasificación aún no está conectado. '
      'No se ha generado ningún resultado. Puedes cambiar la imagen o reintentar más adelante.',
    );
  }

  Future<List<AnalysisResult>> history(String? email) async {
    if (email != 'demo@nerilum.app') return const [];
    return [
      AnalysisResult(
        displayName: 'Exploración inicial',
        category: 'MildDemented',
        createdAt: DateTime(2026, 9, 29, 10, 45),
        probability: 0.84,
        isDemo: true,
      ),
      AnalysisResult(
        displayName: 'Control de seguimiento',
        category: 'NonDemented',
        createdAt: DateTime(2026, 9, 28, 16, 20),
        probability: 0.72,
        isDemo: true,
      ),
      AnalysisResult(
        displayName: 'Revisión de imagen',
        category: 'VeryMildDemented',
        createdAt: DateTime(2026, 9, 25, 8, 15),
        probability: 0.91,
        isDemo: true,
      ),
      AnalysisResult(
        displayName: 'Estudio de referencia',
        category: 'ModerateDemented',
        createdAt: DateTime(2026, 9, 20, 13, 5),
        probability: 0.63,
        isDemo: true,
      ),
    ];
  }
}
