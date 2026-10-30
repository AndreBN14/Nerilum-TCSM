import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/report_repository.dart';
import '../../core/utils/score_text.dart';

class PdfReportRepository implements ReportRepository {
  const PdfReportRepository();

  static const categories = [
    'NonDemented',
    'VeryMildDemented',
    'MildDemented',
    'ModerateDemented',
  ];

  @override
  Future<Uint8List> buildPdf(
    AnalysisResult analysis, {
    Uint8List? imageBytes,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/Lato-Regular.ttf'),
    );
    final bold = pw.Font.ttf(await rootBundle.load('assets/Lato-Bold.ttf'));
    final colors = PdfColor.fromInt(0xFF216B49);
    final pdf = pw.Document(
      title: 'Nerilum - Reporte de análisis de MRI',
      author: 'Nerilum',
    );
    final date = analysis.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    final dateText =
        '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
    // Los registros antiguos no siempre contienen las cuatro puntuaciones.
    final complete = categories.every(analysis.scores.containsKey);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (_) => [
          pw.Text(
            'NERILUM',
            style: pw.TextStyle(color: colors, fontSize: 14, letterSpacing: 2),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Reporte de análisis de MRI',
            style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Análisis: ${analysis.displayName ?? 'Análisis sin nombre'}'),
          pw.Text('Fecha y hora: $dateText'),
          if (imageBytes != null) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              width: 130,
              height: 130,
              child: pw.Image(
                pw.MemoryImage(imageBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.Text(
              'Imagen disponible solo durante esta sesión.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Resultado del modelo: ${analysis.category}',
            style: pw.TextStyle(
              color: colors,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (analysis.probability != null)
            pw.Text(
              'Puntuación del modelo: ${scoreText(analysis.probability!)}',
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Puntuaciones por clase',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (complete)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                children: [
                  for (final name in categories)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 7),
                      child: pw.Row(
                        children: [
                          pw.SizedBox(
                            width: 122,
                            child: pw.Text(
                              name,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Container(
                            width: 150,
                            height: 12,
                            color: PdfColors.grey300,
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Container(
                              width:
                                  150 * analysis.scores[name]!.clamp(0.0, 1.0),
                              height: 12,
                              color: name == analysis.category
                                  ? PdfColor.fromInt(0xFFC6F2D5)
                                  : PdfColor.fromInt(0xFF8CB9A2),
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Expanded(
                            child: pw.Text(
                              scoreText(analysis.scores[name]!),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            pw.Text(
              'No hay puntuaciones completas disponibles para este registro.',
            ),
          if (analysis.modelName != null && analysis.modelVersion != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('Modelo: ${analysis.modelName} · ${analysis.modelVersion}'),
          ],
          pw.SizedBox(height: 24),
          pw.Text(
            'Resultado orientativo generado por un modelo de inteligencia '
            'artificial. No constituye un diagnóstico médico ni sustituye la '
            'evaluación de un profesional de salud.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
