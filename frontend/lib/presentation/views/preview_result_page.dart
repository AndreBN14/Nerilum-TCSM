import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../core/theme/nerilum_theme.dart';
import '../viewmodels/main_view_model.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/class_scores.dart';
import '../widgets/main_components.dart';

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
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver al análisis',
                          onPressed: widget.model.saving ? null : _confirmExit,
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
                      const SizedBox(height: 24),
                      ResultCard(
                        result: preview.result,
                        onTap: null,
                        displayNameOverride:
                            widget.model.analysisName.trim().isEmpty
                            ? null
                            : widget.model.analysisName.trim(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: widget.model.analysisName,
                        enabled: widget.model.canEditPreviewName,
                        maxLength: 120,
                        onChanged: widget.model.setAnalysisName,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del análisis (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClassScores(result: preview.result),
                      const SizedBox(height: 16),
                      const Text(
                        'Este resultado no aparecerá en el historial hasta que lo guardes. '
                        'Si no le asignas nombre, se guardará como “Análisis sin nombre”.',
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
                      MintButton(
                        label: widget.model.saving
                            ? 'Guardando…'
                            : 'Guardar en historial',
                        icon: Icons.save_outlined,
                        onPressed: widget.model.saving ? null : _save,
                      ),
                      TextButton(
                        onPressed: widget.model.saving ? null : _discard,
                        child: const Text('Descartar resultado'),
                      ),
                      const SizedBox(height: 16),
                      const AnalysisDisclaimer(),
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
