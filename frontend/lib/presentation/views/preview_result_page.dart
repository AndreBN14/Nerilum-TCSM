import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/category_label.dart';
import '../../core/utils/score_text.dart';
import '../viewmodels/main_view_model.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/class_scores.dart';
import '../widgets/main_components.dart';
import '../widgets/zoomable_analysis_image.dart';
import 'image_zoom_page.dart';

class PreviewResultPage extends StatefulWidget {
  const PreviewResultPage({
    super.key,
    required this.model,
    required this.onSaved,
  });

  final MainViewModel model;
  final ValueChanged<AnalysisResult> onSaved;

  @override
  State<PreviewResultPage> createState() => _PreviewResultPageState();
}

class _PreviewResultPageState extends State<PreviewResultPage> {
  bool _asking = false;

  void _discard() {
    widget.model.discardPreview();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (widget.model.saving) return;
    await widget.model.savePreview();
    if (!mounted) return;

    // Si falló por storage no disponible, ofrecemos guardar sin imagen.
    if (widget.model.preview != null &&
        widget.model.error != null &&
        widget.model.saveAnalysisWithoutImage != null) {
      final isStorageError = widget.model.error!.toLowerCase().contains(
            'almacenamiento',
          );
      if (isStorageError) {
        await _offerSaveWithoutImage();
        return;
      }
    }

    if (!mounted) return;
    final saved = widget.model.result;
    if (widget.model.preview == null && saved != null) {
      widget.onSaved(saved);
    }
  }

  /// Muestra el diálogo cuando el storage no está disponible.
  /// El usuario elige guardar sin imagen o quedarse en la pantalla.
  Future<void> _offerSaveWithoutImage() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Almacenamiento de imágenes no disponible'),
        content: const Text(
          'No es posible guardar la imagen en este momento. '
          'Puedes guardar el resultado sin imagen o quedarte aquí para intentarlo más tarde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar sin imagen'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    // Limpiar el error antes de reintentar sin imagen.
    widget.model.clearError();
    await widget.model.savePreviewWithoutImage();
    if (!mounted) return;
    final saved = widget.model.result;
    if (widget.model.preview == null && saved != null) {
      widget.onSaved(saved);
    }
  }

  Future<void> _confirmExit() async {
    if (_asking || widget.model.saving) return;
    if (widget.model.preview == null) {
      Navigator.of(context).pop();
      return;
    }
    _asking = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resultado sin guardar'),
          content: const Text(
            'Si sales sin guardar, perderás este análisis. ¿Qué deseas hacer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'stay'),
              child: const Text('Seguir aquí'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: const Text('Salir sin guardar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'discard') _discard();
      if (choice == 'save') await _save();
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final preview = widget.model.preview;
      final colors = NerilumPalette.of(context);
      final image = widget.model.image;
      return PopScope(
        canPop: preview == null && !widget.model.saving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          body: BrandBackdrop(
            child: SafeArea(
              child: MainPageWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
                  children: [
                    // ── Header ─────────────────────────────────────────
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver al análisis',
                          onPressed:
                              widget.model.saving ? null : _confirmExit,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Expanded(
                          child: Text(
                            'Resultado sin guardar',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),

                    if (preview == null && widget.model.pendingError != null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(widget.model.pendingError!),
                      ),

                    if (preview != null) ...[
                      const SizedBox(height: 20),

                      // ── Imagen con zoom ────────────────────────────
                      if (image != null)
                        _ImagePreviewCard(
                          image: image,
                          gradcam: preview.gradcam,
                          colors: colors,
                        ),

                      const SizedBox(height: 16),

                      // ── Resultado + nombre editable ────────────────
                      _ResultHeader(
                        preview: preview,
                        colors: colors,
                        analysisName: widget.model.analysisName,
                        canEdit: widget.model.canEditPreviewName,
                        onChanged: widget.model.setAnalysisName,
                        onDone: () => FocusScope.of(context).unfocus(),
                      ),

                      const SizedBox(height: 12),

                      // ── Distribución de clases ─────────────────────
                      ClassScores(result: preview.result),

                      const SizedBox(height: 14),

                      // ── Aviso unificado ────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Resultado orientativo · No es diagnóstico médico. '
                                'No se guardará en el historial hasta que lo confirmes.',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (widget.model.error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            widget.model.error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Acciones ───────────────────────────────────
                      MintButton(
                        label: widget.model.saving
                            ? 'Guardando\u2026'
                            : 'Guardar en historial',
                        icon: Icons.save_outlined,
                        onPressed: widget.model.saving ? null : _save,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: widget.model.saving ? null : _discard,
                        child: const Text('Descartar resultado'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ── Subwidgets ──────────────────────────────────────────────────────────────

class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({
    required this.image,
    required this.colors,
    this.gradcam,
  });
  final SelectedImage image;
  final NerilumPalette colors;
  final Uint8List? gradcam;

  @override
  Widget build(BuildContext context) {
    final gradcamBytes = gradcam;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: gradcamBytes == null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 210,
                width: double.infinity,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImageZoomPage(image: image),
                    ),
                  ),
                  child: Semantics(
                    label: 'Ampliar imagen analizada',
                    button: true,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          image.bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            color: colors.textSecondary,
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ZoomableAnalysisImage(
                        bytes: image.bytes,
                        label: 'IRM original',
                        zoomName: image.name,
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ZoomableAnalysisImage(
                        bytes: gradcamBytes,
                        label: 'Mapa de atención',
                        zoomName: 'Mapa de atención',
                        colors: colors,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'El mapa de atención muestra en qué zonas se fijó más el '
                  'sistema. No identifica lesiones ni sustituye una valoración '
                  'médica.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.preview,
    required this.colors,
    required this.analysisName,
    required this.canEdit,
    required this.onChanged,
    required this.onDone,
  });

  final dynamic preview;
  final NerilumPalette colors;
  final String analysisName;
  final bool canEdit;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final result = preview.result as AnalysisResult;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre editable
          TextFormField(
            initialValue: analysisName,
            enabled: canEdit,
            maxLength: 120,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onDone(),
            onChanged: onChanged,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Nombre del análisis (opcional)',
              hintText: 'Análisis sin nombre',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
          Divider(color: colors.border, height: 24),
          // Resultado del modelo
          Text(
            'Clase estimada',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            categoryLabel(result.category),
            style: TextStyle(
              color: colors.mint,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (result.probability != null) ...[
            const SizedBox(height: 8),
            Text(
              'Puntuaci\u00f3n del modelo: ${scoreText(result.probability!)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
