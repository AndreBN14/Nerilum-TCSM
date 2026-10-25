import 'dart:typed_data';

import '../models/analysis_result.dart';

abstract class ReportRepository {
  Future<Uint8List> buildPdf(AnalysisResult analysis, {Uint8List? imageBytes});
}
