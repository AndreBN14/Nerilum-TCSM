import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../core/theme/nerilum_theme.dart';
import 'brand_backdrop.dart';

class MainPageWidth extends StatelessWidget {
  const MainPageWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: child,
    ),
  );
}

class MintButton extends StatelessWidget {
  const MintButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Text(label, textAlign: TextAlign.center)),
        const SizedBox(width: 12),
        Icon(icon),
      ],
    ),
  );
}

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Container(
      color: colors.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 64, color: colors.textSecondary),
          const SizedBox(height: 12),
          Text(
            'Ninguna imagen seleccionada',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class EmptyHistory extends StatelessWidget {
  const EmptyHistory({super.key, required this.onSelect});
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.history, size: 36, color: colors.mintSecondary),
          const SizedBox(height: 12),
          const Text(
            'Aún no tienes análisis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Cuando haya resultados reales disponibles, aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSelect,
            child: const Text('Seleccionar imagen'),
          ),
        ],
      ),
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.result,
    required this.onTap,
    this.titleContent,
  });

  final AnalysisResult result;
  final VoidCallback? onTap;

  /// Only the unsaved preview supplies an editable title. Saved cards stay read-only.
  final Widget? titleContent;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final date = result.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${two(date.day)}/${two(date.month)}/${date.year} · '
                '${two(date.hour)}:${two(date.minute)}',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              titleContent ??
                  Text(
                    result.displayName ?? 'Análisis sin nombre',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'Clase estimada: ${result.category}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.mintSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                result.probability == null
                    ? 'Probabilidad: —'
                    : 'Probabilidad: ${(result.probability! * 100).toStringAsFixed(0)} %',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalysisDisclaimer extends StatelessWidget {
  const AnalysisDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Row(
      children: [
        Icon(Icons.info_outline, size: 20, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Resultado orientativo · No es diagnóstico médico.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BrandBackdrop(
      child: SafeArea(
        child: MainPageWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 36),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}
