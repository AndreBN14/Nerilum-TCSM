import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../core/theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/main_components.dart';
import '../../core/utils/score_text.dart';
import '../widgets/class_scores.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final date = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');

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
                ClassScores(result: result),
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
