import 'dart:typed_data';

import '../models/analysis_result.dart';
import '../repositories/report_repository.dart';

class GenerateReport {
  const GenerateReport(this.repository);
  final ReportRepository repository;
  Future<Uint8List> call(AnalysisResult result, {Uint8List? imageBytes}) =>
      repository.buildPdf(result, imageBytes: imageBytes);
}
