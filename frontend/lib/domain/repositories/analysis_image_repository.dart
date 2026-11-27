import 'dart:typed_data';

abstract class AnalysisImageRepository {
  Future<Uint8List> loadImage(String analysisId);
  Future<Uint8List> loadGradcam(String analysisId);
}
