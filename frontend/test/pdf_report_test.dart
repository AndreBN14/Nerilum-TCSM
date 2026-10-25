import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/repositories/pdf_report_repository.dart';
import 'package:frontend/domain/models/analysis_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final result = AnalysisResult(
    id: 'an_abc',
    displayName: 'Revisión anual',
    category: 'VeryMildDemented',
    createdAt: DateTime.utc(2026, 10, 24, 9, 15),
    probability: .72,
    scores: const {
      'NonDemented': .08,
      'VeryMildDemented': .72,
      'MildDemented': .16,
      'ModerateDemented': .04,
    },
    modelName: 'yolov8n-cls',
    modelVersion: 'v0.1',
  );

  test(
    'El PDF se crea desde un registro sin volver a analizar ni guardar',
    () async {
      final pdf = await const PdfReportRepository().buildPdf(result);
      expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(1500));
    },
  );

  test(
    'Imagen disponible solo en sesión y registros incompletos generan PDF',
    () async {
      final data = await rootBundle.load('assets/nerilum-mark-512.png');
      final image = data.buffer.asUint8List();
      final repository = const PdfReportRepository();
      final withImage = await repository.buildPdf(result, imageBytes: image);
      final noScores = await repository.buildPdf(
        AnalysisResult(
          category: 'MildDemented',
          createdAt: DateTime.utc(2026, 10, 24),
        ),
      );
      expect(withImage.length, greaterThan(noScores.length));
      expect(utf8.decode(noScores.sublist(0, 5)), '%PDF-');
    },
  );
}
