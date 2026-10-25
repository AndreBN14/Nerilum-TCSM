import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/analysis_preview.dart';
import '../../domain/models/selected_image.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/main_components.dart';
import '../widgets/class_scores.dart';

class AnalysisView extends StatelessWidget {
  const AnalysisView({
    super.key,
    required this.image,
    required this.result,
    this.preview,
    this.saving = false,
    this.onSave,
    this.onDiscard,
    required this.error,
    required this.processing,
    required this.onBack,
    required this.onPick,
    required this.onRemove,
    required this.onAnalyze,
    required this.analysisName,
    required this.onNameChanged,
  });

  final SelectedImage? image;
  final AnalysisResult? result;
  final AnalysisPreview? preview;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final String? error;
  final bool processing;
  final VoidCallback onBack;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onAnalyze;
  final String analysisName;
  final ValueChanged<String> onNameChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return MainPageWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver a Inicio',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(
                child: Text(
                  'Nuevo análisis',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Selecciona una imagen MRI cerebral',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            'Carga una imagen JPG o PNG (hasta 10 MB) para explorar el flujo académico.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: image == null
                        ? const ImagePlaceholder()
                        : Image.memory(
                            image!.bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const ImagePlaceholder(),
                          ),
                  ),
                ),
                if (image != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                image!.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                image!.extension.toUpperCase(),
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar imagen',
                          onPressed: processing || saving ? null : onRemove,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (image != null) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey(image),
              initialValue: analysisName,
              enabled: !processing && !saving && result == null,
              maxLength: 120,
              onChanged: onNameChanged,
              decoration: const InputDecoration(
                labelText: 'Nombre del análisis (opcional)',
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: colors.error, fontSize: 14),
              ),
            ),
          ],
          if (preview != null || result != null) ...[
            const SizedBox(height: 16),
            if (preview != null)
              const Text(
                'Resultado sin guardar',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 10),
            ResultCard(
              result: (preview?.result ?? result)!,
              onTap: null,
              displayNameOverride:
                  preview == null || analysisName.trim().isEmpty
                  ? null
                  : analysisName.trim(),
            ),
            const SizedBox(height: 12),
            Text(
              'Categoría del modelo: ${(preview?.result ?? result)!.category}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (preview != null) ...[
              const SizedBox(height: 20),
              ClassScores(result: preview!.result),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Este resultado no aparecerá en el historial hasta que lo guardes. '
                'Si no le asignas nombre, se guardará como “Análisis sin nombre”.',
              ),
              const SizedBox(height: 16),
              MintButton(
                label: saving ? 'Guardando…' : 'Guardar en historial',
                icon: Icons.save_outlined,
                onPressed: saving ? null : onSave,
              ),
              TextButton(
                onPressed: saving ? null : onDiscard,
                child: const Text('Descartar resultado'),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Guardado en el historial'),
              ),
          ],
          const SizedBox(height: 20),
          MintButton(
            label: processing
                ? 'Analizando imagen'
                : preview != null
                ? 'Resultado listo para guardar'
                : result != null
                ? 'Análisis completado'
                : error == null
                ? 'Analizar imagen'
                : 'Reintentar análisis',
            icon: processing ? Icons.hourglass_top : Icons.arrow_forward,
            onPressed:
                image == null ||
                    processing ||
                    saving ||
                    preview != null ||
                    result != null
                ? null
                : onAnalyze,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: processing || saving ? null : onPick,
            icon: Icon(image == null ? Icons.image_outlined : Icons.sync),
            label: Text(
              image == null ? 'Seleccionar imagen' : 'Cambiar imagen',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.border),
            ),
          ),
          const SizedBox(height: 28),
          const AnalysisDisclaimer(),
        ],
      ),
    );
  }
}
