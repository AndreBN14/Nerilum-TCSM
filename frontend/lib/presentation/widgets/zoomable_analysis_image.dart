import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../domain/models/selected_image.dart';
import '../views/image_zoom_page.dart';

/// Imagen cuadrada con etiqueta, tappable para abrirla a pantalla completa.
///
/// Se usa para mostrar la IRM original y el Grad-CAM lado a lado conservando la
/// misma interacción de zoom en ambas.
class ZoomableAnalysisImage extends StatelessWidget {
  const ZoomableAnalysisImage({
    super.key,
    required this.bytes,
    required this.label,
    required this.zoomName,
    required this.colors,
    this.height = 150,
  });

  final Uint8List? bytes;
  final String label;
  final String zoomName;
  final NerilumPalette colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: height,
            child: image == null
                ? Container(
                    color: colors.surface,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: colors.textSecondary,
                    ),
                  )
                : InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImageZoomPage(
                          image: SelectedImage(
                            bytes: image,
                            name: zoomName,
                            extension: 'png',
                          ),
                        ),
                      ),
                    ),
                    child: Semantics(
                      label: 'Ampliar $label',
                      button: true,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            color: Colors.black,
                            child: Image.memory(
                              image,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.broken_image_outlined,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.all(4),
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
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
