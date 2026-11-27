import 'dart:typed_data';

import 'analysis_result.dart';

class AnalysisPreview {
  const AnalysisPreview({
    required this.result,
    required this.saveProof,
    required this.expiresAt,
    this.gradcam,
  });

  final AnalysisResult result;
  final String saveProof;
  final DateTime expiresAt;

  /// PNG del mapa generado durante la previsualización. Al confirmar el
  /// guardado, el backend lo persiste y puede descargarse después.
  final Uint8List? gradcam;
}
