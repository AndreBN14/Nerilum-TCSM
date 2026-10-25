import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/main_components.dart';
import '../../domain/formatters/score_text.dart';

class AnalysisDetailView extends StatelessWidget {
  const AnalysisDetailView({
    super.key,
    required this.result,
    required this.imageBytes,
    required this.onBack,
    this.onExport,
    this.onShare,
    this.exporting = false,
  });

  final AnalysisResult result;
  final Uint8List? imageBytes;
  final VoidCallback onBack;
  final VoidCallback? onExport;
  final VoidCallback? onShare;
  final bool exporting;

  static const categories = [
    'NonDemented',
    'VeryMildDemented',
    'MildDemented',
    'ModerateDemented',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final date = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final complete = categories.every(result.scores.containsKey);

    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: MainPageWidth(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver al historial',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Detalle del análisis',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 92,
                        height: 92,
                        color: colors.surface,
                        child: imageBytes == null
                            ? Icon(
                                Icons.insert_drive_file_outlined,
                                color: colors.textSecondary,
                                size: 36,
                              )
                            : Image.memory(
                                imageBytes!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: colors.textSecondary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.displayName ?? 'Análisis sin nombre',
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${two(date.day)}/${two(date.month)}/${date.year} · '
                            '${two(date.hour)}:${two(date.minute)}',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resultado del modelo',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.category,
                        style: TextStyle(
                          color: colors.mint,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (result.probability != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Puntuación del modelo: ${scoreText(result.probability!)}',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Probabilidades por clase',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Puntuaciones del modelo; no son probabilidades clínicas.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (complete) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      children: [
                        for (final category in categories)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    category,
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Semantics(
                                    label:
                                        '$category: ${scoreText(result.scores[category]!)}',
                                    child: LinearProgressIndicator(
                                      value: result.scores[category]!.clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      minHeight: 14,
                                      borderRadius: BorderRadius.circular(3),
                                      color: category == result.category
                                          ? colors.mint
                                          : colors.mintSecondary,
                                      backgroundColor: colors.surfaceRaised,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 63,
                                  child: Text(
                                    scoreText(result.scores[category]!),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Table(
                    border: TableBorder.all(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Clase'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Puntuación'),
                          ),
                        ],
                      ),
                      for (final category in categories)
                        TableRow(
                          decoration: category == result.category
                              ? BoxDecoration(color: colors.surfaceRaised)
                              : null,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                category,
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: category == result.category
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                scoreText(result.scores[category]!),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ] else
                  const Text(
                    'Puntuaciones por clase no disponibles para este registro.',
                  ),
                const SizedBox(height: 20),
                if (result.modelName != null && result.modelVersion != null)
                  Text(
                    'Modelo: ${result.modelName} · ${result.modelVersion}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: exporting ? null : onExport,
                  icon: Icon(
                    exporting
                        ? Icons.hourglass_top
                        : Icons.picture_as_pdf_outlined,
                  ),
                  label: Text(
                    exporting ? 'Generando PDF…' : 'Generar reporte PDF',
                  ),
                ),
                TextButton.icon(
                  onPressed: exporting ? null : onShare,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartir reporte PDF'),
                ),
                Text(
                  'En la vista previa puedes elegir Guardar como PDF; el archivo '
                  'quedará donde selecciones en tu dispositivo.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                const AnalysisDisclaimer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
