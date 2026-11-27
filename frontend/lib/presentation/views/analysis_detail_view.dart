import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/category_label.dart';
import '../../core/utils/score_text.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/class_scores.dart';
import '../widgets/main_components.dart';
import '../widgets/zoomable_analysis_image.dart';
import 'image_zoom_page.dart';

class AnalysisDetailView extends StatelessWidget {
  const AnalysisDetailView({
    super.key,
    required this.result,
    required this.imageBytes,
    required this.onBack,
    this.gradcamBytes,
    this.onExport,
    this.onShare,
    this.onRetryImage,
    this.exporting = false,
    this.imageLoading = false,
    this.imageError,
  });

  final AnalysisResult result;
  final Uint8List? imageBytes;
  /// Mapa en memoria tras guardar; si falta, se descarga del backend.
  final Uint8List? gradcamBytes;
  final VoidCallback onBack;
  final VoidCallback? onExport;
  final VoidCallback? onShare;
  /// Called when the user taps "Reintentar" in the image error state.
  final VoidCallback? onRetryImage;
  final bool exporting;
  final bool imageLoading;
  final String? imageError;

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
                  gradcamBytes: gradcamBytes,
                  displayName: result.displayName,
                  dateStr: dateStr,
                  hasImage: result.hasImage,
                  imageLoading: imageLoading,
                  imageError: imageError,
                  onRetryImage: onRetryImage,
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
                  imageLoading: imageLoading,
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
    required this.gradcamBytes,
    required this.displayName,
    required this.dateStr,
    required this.hasImage,
    required this.imageLoading,
    required this.imageError,
    required this.onRetryImage,
    required this.colors,
  });

  final Uint8List? imageBytes;
  final Uint8List? gradcamBytes;
  final String? displayName;
  final String dateStr;
  final bool hasImage;
  final bool imageLoading;
  final String? imageError;
  final VoidCallback? onRetryImage;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    final gradcam = gradcamBytes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: gradcam == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Miniatura / estado de imagen
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: _ImageSlot(
                      imageBytes: imageBytes,
                      displayName: displayName,
                      hasImage: hasImage,
                      imageLoading: imageLoading,
                      imageError: imageError,
                      onRetry: onRetryImage,
                      colors: colors,
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
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ZoomableAnalysisImage(
                        bytes: imageBytes,
                        label: 'IRM original',
                        zoomName: displayName ?? 'Imagen del análisis',
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ZoomableAnalysisImage(
                        bytes: gradcam,
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

/// El cuadrado de 88×88 que muestra uno de cuatro estados:
///   • imagen cargada  → tappable con badge de zoom
///   • cargando        → shimmer animado
///   • error de carga  → icono de error + botón reintentar
///   • sin imagen      → placeholder neutro con icono de archivo
class _ImageSlot extends StatelessWidget {
  const _ImageSlot({
    required this.imageBytes,
    required this.displayName,
    required this.hasImage,
    required this.imageLoading,
    required this.imageError,
    required this.onRetry,
    required this.colors,
  });

  final Uint8List? imageBytes;
  final String? displayName;
  final bool hasImage;
  final bool imageLoading;
  final String? imageError;
  final VoidCallback? onRetry;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    // ① Imagen disponible
    if (imageBytes != null) {
      return _ZoomableThumbnail(
        imageBytes: imageBytes!,
        displayName: displayName,
        colors: colors,
      );
    }

    // ② Cargando desde el servidor
    if (imageLoading) {
      return _ShimmerPlaceholder(colors: colors);
    }

    // ③ Error de carga — con botón reintentar si hay callback
    if (imageError != null) {
      return _ErrorSlot(
        colors: colors,
        onRetry: onRetry,
      );
    }

    // ④ Sin imagen (análisis guardado sin foto)
    if (!hasImage) {
      return _NoImageSlot(colors: colors);
    }

    // Transitorio: hasImage=true pero aún no hay bytes ni carga activa
    return _ShimmerPlaceholder(colors: colors);
  }
}

/// Imagen lista: tappable, abre zoom, badge de lupa.
class _ZoomableThumbnail extends StatelessWidget {
  const _ZoomableThumbnail({
    required this.imageBytes,
    required this.displayName,
    required this.colors,
  });
  final Uint8List imageBytes;
  final String? displayName;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageZoomPage(
            image: SelectedImage(
              bytes: imageBytes,
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
              imageBytes,
              fit: BoxFit.cover,
              cacheWidth: 256,
              errorBuilder: (context, error, stackTrace) => _BrokenImageSlot(colors: colors),
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
    );
  }
}

/// Shimmer animado mientras la imagen se descarga del servidor.
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder({required this.colors});
  final NerilumPalette colors;

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.colors.surfaceRaised;
    final highlight = widget.colors.border;
    return Semantics(
      label: 'Cargando imagen…',
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(base, highlight, _anim.value)!,
                Color.lerp(highlight, base, _anim.value)!,
              ],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.colors.mintSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error de carga: icono + etiqueta + botón reintentar si hay callback.
class _ErrorSlot extends StatelessWidget {
  const _ErrorSlot({required this.colors, required this.onRetry});
  final NerilumPalette colors;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'No se pudo cargar la imagen',
      child: Container(
        color: colors.surfaceRaised,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: colors.error,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              'Sin imagen',
              style: TextStyle(
                color: colors.error,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.error.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Reintentar',
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sin imagen: este análisis fue guardado sin foto.
class _NoImageSlot extends StatelessWidget {
  const _NoImageSlot({required this.colors});
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Este análisis no tiene imagen',
      child: Container(
        color: colors.surfaceRaised,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hide_image_outlined,
              color: colors.textSecondary,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              'Sin imagen',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Imagen corrupta: el decoder de Flutter falló al renderizarla.
class _BrokenImageSlot extends StatelessWidget {
  const _BrokenImageSlot({required this.colors});
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceRaised,
      child: Icon(
        Icons.broken_image_outlined,
        color: colors.textSecondary,
        size: 28,
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
    required this.imageLoading,
    required this.onExport,
    required this.onShare,
    required this.colors,
  });

  final bool exporting;
  final bool imageLoading;
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
          onPressed: exporting || imageLoading ? null : onExport,
        ),
      ],
    );
  }
}
