import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/score_text.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';

/// Categorías que muestra el detalle, en el mismo orden que el backend.
const _scoreCategories = [
  'NonDemented',
  'VeryMildDemented',
  'MildDemented',
  'ModerateDemented',
];

/// Vista Detalle de análisis del portal web.
///
/// Datos necesarios: GET /api/v1/analyses/{id}
/// Requiere [analysisSource] con token de Supabase ya configurado.
class WebAnalysisDetailScreen extends StatefulWidget {
  const WebAnalysisDetailScreen({
    super.key,
    required this.analysisId,
    required this.user,
    this.analysisSource,
    this.onOpenReport,
  });

  final String analysisId;
  final User user;
  // null cuando API_BASE_URL no está configurada.
  final HttpAnalysisDataSource? analysisSource;
  final VoidCallback? onOpenReport;

  @override
  State<WebAnalysisDetailScreen> createState() =>
      _WebAnalysisDetailScreenState();
}

class _WebAnalysisDetailScreenState extends State<WebAnalysisDetailScreen> {
  WebViewStatus _status = WebViewStatus.loading;
  AnalysisResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = WebViewStatus.loading;
      _error = null;
    });

    final source = widget.analysisSource;
    if (source == null) {
      if (!mounted) return;
      setState(() {
        _error = 'El backend de análisis no está configurado. '
            'Define API_BASE_URL al ejecutar la app.';
        _status = WebViewStatus.error;
      });
      return;
    }

    try {
      // GET /api/v1/analyses/{id} — devuelve null si no existe o no pertenece
      // al usuario autenticado (404).
      final result = await source.findById(widget.analysisId);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _status = WebViewStatus.empty;
          _error = null;
        });
      } else {
        setState(() {
          _result = result;
          _status = WebViewStatus.content;
        });
      }
    } on AnalysisFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _status = isSessionExpiredError(e.message)
            ? WebViewStatus.sessionExpired
            : WebViewStatus.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el análisis. Inténtalo de nuevo.';
        _status = WebViewStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Volver',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Expanded(
                        child: Text(
                          'Detalle del análisis',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Divider(color: colors.border, height: 24),
                  Expanded(
                    child: WebViewStateBox(
                      status: _status,
                      loadingBuilder: (_) => const DetailSkeleton(),
                      onRetry: _load,
                      emptyTitle: 'Análisis no encontrado',
                      emptyHint:
                          'Este análisis no existe o no pertenece a tu cuenta.',
                      errorMessage: _error ?? 'No se pudo cargar el análisis.',
                      content: _result == null
                          ? const SizedBox.shrink()
                          : _DetailContent(
                              result: _result!,
                              onOpenReport: widget.onOpenReport,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Contenido del detalle ────────────────────────────────────────────────────

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.result, this.onOpenReport});

  final AnalysisResult result;
  final VoidCallback? onOpenReport;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final d = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr =
        '${two(d.day)}/${two(d.month)}/${d.year} · '
        '${two(d.hour)}:${two(d.minute)}';

    return ListView(
      children: [
        // Nombre y fecha
        _SurfaceCard(
          colors: colors,
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.displayName ?? 'Análisis sin nombre',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
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
        ),
        const SizedBox(height: 12),

        // Categoría ganadora + indicador demo
        _SurfaceCard(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Categoría del modelo',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    result.category,
                    style: TextStyle(
                      color: colors.mint,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (result.isDemo) ...[
                    const SizedBox(width: 12),
                    _DemoBadge(colors: colors),
                  ],
                ],
              ),
              if (result.probability != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Puntuación del modelo: ${scoreText(result.probability!)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
              if (result.modelName != null && result.modelVersion != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Modelo: ${result.modelName} · ${result.modelVersion}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Las 4 puntuaciones
        const Text(
          'Probabilidades por clase',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Salidas del modelo; no son probabilidades clínicas.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _SurfaceCard(
          colors: colors,
          child: _scoreCategories.every(result.scores.containsKey)
              ? Column(
                  children: [
                    for (final cat in _scoreCategories)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                cat,
                                maxLines: 2,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Semantics(
                                label: '$cat: ${scoreText(result.scores[cat]!)}',
                                child: LinearProgressIndicator(
                                  value: result.scores[cat]!.clamp(0, 1),
                                  minHeight: 14,
                                  borderRadius: BorderRadius.circular(3),
                                  color: cat == result.category
                                      ? colors.mint
                                      : colors.mintSecondary,
                                  backgroundColor: colors.surfaceRaised,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: Text(
                                scoreText(result.scores[cat]!),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              : Text(
                  'Puntuaciones por clase no disponibles para este resultado.',
                  style: TextStyle(color: colors.textSecondary),
                ),
        ),
        const SizedBox(height: 20),

        // Acción: abrir reporte
        ElevatedButton.icon(
          onPressed: onOpenReport,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Descargar reporte PDF'),
        ),
        const SizedBox(height: 20),
        const _MedicalNotice(),
      ],
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.colors, required this.child});
  final NerilumPalette colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge({required this.colors});
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.mint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.mint.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'demo',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MedicalNotice extends StatelessWidget {
  const _MedicalNotice();

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined,
              size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Resultado orientativo generado por un modelo de IA. No constituye '
              'un diagnóstico médico ni sustituye la evaluación de un '
              'profesional de salud.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
