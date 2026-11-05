import 'package:flutter/material.dart';

import '../../domain/models/selected_image.dart';
import '../../core/theme/nerilum_theme.dart';
import '../widgets/main_components.dart';
import 'image_zoom_page.dart';

class AnalysisView extends StatelessWidget {
  const AnalysisView({
    super.key,
    required this.image,
    required this.error,
    required this.processing,
    required this.onBack,
    required this.onPick,
    required this.onRemove,
    required this.onAnalyze,
    this.onQueue,
    this.pendingError,
  });

  final SelectedImage? image;
  final String? error;
  final bool processing;
  final VoidCallback onBack;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onAnalyze;
  final VoidCallback? onQueue;
  final String? pendingError;

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
                        ? Semantics(
                            button: true,
                            label: 'Seleccionar imagen',
                            child: InkWell(
                              onTap: processing ? null : onPick,
                              child: const ImagePlaceholder(),
                            ),
                          )
                        : InkWell(
                            key: const ValueKey('selected-image-zoom'),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ImageZoomPage(image: image!),
                              ),
                            ),
                            child: Semantics(
                              label: 'Ampliar imagen seleccionada',
                              button: true,
                              child: Image.memory(
                                image!.bytes,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const ImagePlaceholder(),
                              ),
                            ),
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
                          onPressed: processing ? null : onRemove,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
          if (pendingError != null) ...[
            const SizedBox(height: 10),
            Text(pendingError!, style: TextStyle(color: colors.error)),
          ],
          if (onQueue != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onQueue,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar imagen pendiente en el dispositivo'),
            ),
          ],
          const SizedBox(height: 20),
          MintButton(
            label: processing
                ? 'Analizando imagen'
                : error == null
                ? 'Analizar imagen'
                : 'Reintentar análisis',
            icon: processing ? Icons.hourglass_top : Icons.arrow_forward,
            onPressed: image == null || processing ? null : onAnalyze,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: processing ? null : onPick,
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
