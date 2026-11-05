import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/score_text.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/class_scores.dart';
import '../widgets/main_components.dart';
import 'image_zoom_page.dart';

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
    final dateStr =
        '${two(date.day)}/${two(date.month)}/${date.year} · '
        '${two(date.hour)}:${two(date.minute)}';

    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: MainPageWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
              children: [
                // ── Header ───────────────────────────────────────────────
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

                const SizedBox(height: 20),

                // ── Cabecera: imagen + nombre + fecha ─────────────────────
                _HeaderCard(
                  imageBytes: imageBytes,
                  displayName: result.displayName,
                  dateStr: dateStr,
                  colors: colors,
                ),

                const SizedBox(height: 12),

                // ── Resultado principal ───────────────────────────────────
                _ResultCard(result: result, colors: colors),

                const SizedBox(height: 12),

                // ── Distribución de clases ────────────────────────────────
                ClassScores(result: result),

                const SizedBox(height: 20),

                // ── Acciones de exportar ──────────────────────────────────
                _ExportActions(
                  exporting: exporting,
                  onExport: onExport,
                  onShare: onShare,
                  colors: colors,
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

// ── Subwidgets ──────────────────────────────────────────────────────────────

/// Cabecera unificada: miniatura tappable a la izquierda, nombre y fecha a la derecha.
/// Tocar la miniatura abre la imagen a pantalla completa con zoom.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.imageBytes,
    required this.displayName,
    required this.dateStr,
    required this.colors,
  });

  final Uint8List? imageBytes;
  final String? displayName;
  final String dateStr;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Miniatura con zoom
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 88,
              height: 88,
              child: imageBytes == null
                  ? Container(
                      color: colors.surfaceRaised,
                      child: Icon(
                        Icons.insert_drive_file_outlined,
                        color: colors.textSecondary,
                        size: 32,
                      ),
                    )
                  : InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ImageZoomPage(
                            image: SelectedImage(
                              bytes: imageBytes!,
                              name: displayName ?? 'Imagen del análisis',
                              extension: 'jpg',
                            ),
                          ),
                        ),
                      ),
                      child: Semantics(
                        label: 'Ampliar imagen del análisis',
                        button: true,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              imageBytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.broken_image_outlined,
                                color: colors.textSecondary,
                              ),
                            ),
                            // Badge de zoom
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          // Nombre y fecha
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName ?? 'Análisis sin nombre',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.colors});

  final AnalysisResult result;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clase estimada',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            result.category,
            style: TextStyle(
              color: colors.mint,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (result.probability != null) ...[
            const SizedBox(height: 8),
            Text(
              'Puntuación del modelo: ${scoreText(result.probability!)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          if (result.modelName != null && result.modelVersion != null) ...[
            Divider(color: colors.border, height: 22),
            Text(
              'Modelo: ${result.modelName} · ${result.modelVersion}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExportActions extends StatelessWidget {
  const _ExportActions({
    required this.exporting,
    required this.onExport,
    required this.onShare,
    required this.colors,
  });

  final bool exporting;
  final VoidCallback? onExport;
  final VoidCallback? onShare;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MintButton(
          label: exporting ? 'Generando PDF\u2026' : 'Exportar reporte PDF',
          icon: exporting ? Icons.hourglass_top : Icons.picture_as_pdf_outlined,
          onPressed: exporting ? null : onExport,
        ),
      ],
    );
  }
}
