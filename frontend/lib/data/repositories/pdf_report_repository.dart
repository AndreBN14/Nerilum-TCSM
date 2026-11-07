import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;

import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/report_repository.dart';
import '../../core/utils/category_label.dart';
import '../../core/utils/score_text.dart';

// ── Paleta Nerilum para PDF ──────────────────────────────────────────────────
const _kMint = PdfColor(0.129, 0.420, 0.286);         // #216B49
const _kMintLight = PdfColor(0.776, 0.949, 0.835);    // #C6F2D5
const _kMintMid = PdfColor(0.549, 0.725, 0.635);      // #8CB9A2
const _kSurface = PdfColor(0.965, 0.976, 0.969);      // #F6F9F7
const _kBorder = PdfColor(0.820, 0.871, 0.843);       // #D1DED7
const _kText = PdfColor(0.110, 0.157, 0.133);         // #1C2822
const _kTextSecondary = PdfColor(0.200, 0.267, 0.231);// #334438 — oscuro legible

class PdfReportRepository implements ReportRepository {
  const PdfReportRepository();

  static const _categories = [
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
    // ── Preprocesar imagen ───────────────────────────────────────────────────
    Uint8List? reportImage = imageBytes;
    if (imageBytes != null) {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        throw const FormatException('Imagen no válida para el PDF');
      }
      final maxSide =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (maxSide > 1200) {
        final resized = img.copyResize(
          decoded,
          width: (decoded.width * 1200 / maxSide).round(),
          height: (decoded.height * 1200 / maxSide).round(),
        );
        reportImage =
            Uint8List.fromList(img.encodeJpg(resized, quality: 90));
      }
    }

    // ── Fuentes ──────────────────────────────────────────────────────────────
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/Lato-Regular.ttf'),
    );
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/Lato-Bold.ttf'));

    // ── Logo ─────────────────────────────────────────────────────────────────
    final logoData = await rootBundle.load('assets/nerilum-app-icon-1024-recorte.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    // ── Datos del análisis ───────────────────────────────────────────────────
    final date = analysis.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final dateText =
        '${two(date.day)}/${two(date.month)}/${date.year}  '
        '${two(date.hour)}:${two(date.minute)}';

    final complete = _categories.every(analysis.scores.containsKey);

    // ── Documento ────────────────────────────────────────────────────────────
    final pdf = pw.Document(
      title: 'Nerilum – Reporte de análisis de MRI',
      author: 'Nerilum',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        // ── Encabezado de página (se repite) ────────────────────────────────
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logoImage, height: 28, width: 28),
              pw.Text(
                'Reporte de análisis de MRI',
                style: pw.TextStyle(
                  color: _kTextSecondary,
                  fontSize: 10,
                  font: regular,
                ),
              ),
            ],
          ),
        ),
        // ── Pie de página ────────────────────────────────────────────────────
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Resultado orientativo · No constituye diagnóstico médico',
                style: pw.TextStyle(
                  color: _kTextSecondary,
                  fontSize: 8,
                  font: regular,
                ),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(
                  color: _kTextSecondary,
                  fontSize: 8,
                  font: regular,
                ),
              ),
            ],
          ),
        ),
        build: (_) => [
          // ── Línea de acento bajo el encabezado ──────────────────────────
          pw.Container(height: 2, color: _kMint),
          pw.SizedBox(height: 28),

          // ── Título del reporte ───────────────────────────────────────────
          pw.Text(
            analysis.displayName ?? 'Análisis sin nombre',
            style: pw.TextStyle(
              font: bold,
              fontSize: 22,
              color: _kText,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Fecha y hora: $dateText',
            style: pw.TextStyle(
              font: regular,
              fontSize: 11,
              color: _kTextSecondary,
            ),
          ),
          pw.SizedBox(height: 28),

          // ── Imagen del análisis ──────────────────────────────────────────
          if (reportImage != null) ...[
            _sectionLabel('Imagen analizada', bold),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _kBorder, width: 1),
                borderRadius: pw.BorderRadius.circular(6),
                color: _kSurface,
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Center(
                child: pw.ClipRRect(
                  horizontalRadius: 4,
                  verticalRadius: 4,
                  child: pw.ConstrainedBox(
                    constraints: const pw.BoxConstraints(maxHeight: 220),
                    child: pw.Image(
                      pw.MemoryImage(reportImage),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Imagen de resonancia magnética asociada al análisis.',
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: _kTextSecondary,
              ),
            ),
            pw.SizedBox(height: 28),
          ],

          // ── Resultado principal ──────────────────────────────────────────
          _sectionLabel('Resultado del modelo', bold),
          pw.SizedBox(height: 10),
          pw.Container(
            decoration: pw.BoxDecoration(
              color: _kSurface,
              border: pw.Border.all(color: _kBorder, width: 1),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Clase estimada',
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 10,
                    color: _kTextSecondary,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  categoryLabel(analysis.category),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 20,
                    color: _kMint,
                  ),
                ),
                if (analysis.probability != null) ...[
                  pw.SizedBox(height: 8),
                  pw.Container(
                    height: 1,
                    color: _kBorder,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Puntuación del modelo: ${scoreText(analysis.probability!)}',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 11,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
                if (analysis.modelName != null &&
                    analysis.modelVersion != null) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Modelo: ${analysis.modelName}  ·  ${analysis.modelVersion}',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 10,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 28),

          // ── Distribución de clases ───────────────────────────────────────
          _sectionLabel('Distribución de probabilidades por clase', bold),
          pw.SizedBox(height: 4),
          pw.Text(
            'Salidas normalizadas del modelo; no son probabilidades clínicas.',
            style: pw.TextStyle(
              font: regular,
              fontSize: 9,
              color: _kTextSecondary,
            ),
          ),
          pw.SizedBox(height: 10),
          if (complete)
            pw.Container(
              decoration: pw.BoxDecoration(
                color: _kSurface,
                border: pw.Border.all(color: _kBorder, width: 1),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: pw.Column(
                children: [
                  for (int i = 0; i < _categories.length; i++) ...[
                    if (i > 0)
                      pw.Padding(
                        padding:
                            const pw.EdgeInsets.symmetric(vertical: 5),
                        child: pw.Container(
                          height: 0.5,
                          color: _kBorder,
                        ),
                      ),
                    _classRow(
                      name: _categories[i],
                      score: analysis.scores[_categories[i]]!,
                      isWinner:
                          _categories[i] == analysis.category,
                      bold: bold,
                      regular: regular,
                    ),
                  ],
                ],
              ),
            )
          else
            pw.Text(
              'No hay puntuaciones completas disponibles para este registro.',
              style: pw.TextStyle(
                font: regular,
                fontSize: 11,
                color: _kTextSecondary,
              ),
            ),


        ],
      ),
    );

    return pdf.save();
  }

  // ── Helpers de composición ───────────────────────────────────────────────

  static pw.Widget _sectionLabel(String text, pw.Font bold) =>
      pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          font: bold,
          fontSize: 9,
          color: _kTextSecondary,
          letterSpacing: 1.2,
        ),
      );

  static pw.Widget _classRow({
    required String name,
    required double score,
    required bool isWinner,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    const barMaxWidth = 160.0;
    final barWidth = (barMaxWidth * score.clamp(0.0, 1.0));
    final barColor = isWinner ? _kMint : _kMintMid;
    final labelColor = isWinner ? _kText : _kTextSecondary;
    final labelFont = isWinner ? bold : regular;

    return pw.Row(
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            categoryLabel(name),
            style: pw.TextStyle(
              font: labelFont,
              fontSize: 10,
              color: labelColor,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Stack(
          children: [
            pw.Container(
              width: barMaxWidth,
              height: 10,
              decoration: pw.BoxDecoration(
                color: _kMintLight,
                borderRadius: pw.BorderRadius.circular(3),
              ),
            ),
            pw.Container(
              width: barWidth > 0 ? barWidth : 0,
              height: 10,
              decoration: pw.BoxDecoration(
                color: barColor,
                borderRadius: pw.BorderRadius.circular(3),
              ),
            ),
          ],
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 52,
          child: pw.Text(
            scoreText(score),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: labelFont,
              fontSize: 10,
              color: labelColor,
            ),
          ),
        ),
      ],
    );
  }
}
