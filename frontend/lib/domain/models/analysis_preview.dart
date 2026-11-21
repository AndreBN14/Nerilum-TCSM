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

  /// PNG del Grad-CAM generado durante la previsualización. No se persiste:
  /// solo vive en memoria para la pantalla de resultado y el detalle inmediato.
  final Uint8List? gradcam;
}
