import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';

/// Vista Inicio del portal web.
///
/// Muestra: saludo, último análisis, total de análisis y acceso al historial.
///
/// Datos necesarios: resumen derivado de `GET /analyses`.
///
/// Esqueleto: la estructura está lista. La carga real del historial (con el
/// token de Supabase hacia el backend) se marca con TODO. Mientras tanto
/// alterna los 4 estados obligatorios para revisar el andamiaje.
class WebHomeScreen extends StatefulWidget {
  const WebHomeScreen({
    super.key,
    required this.user,
    required this.onOpenHistory,
    required this.onOpenAnalysis,
    this.analysisSource,
  });

  final User user;
  final HttpAnalysisDataSource? analysisSource;
  final VoidCallback onOpenHistory;
  final ValueChanged<String> onOpenAnalysis;

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen> {
  WebViewStatus _status = WebViewStatus.loading;
  int _total = 0;
  AnalysisResult? _last;
  String? _error;

  String get _displayName {
    final meta = widget.user.userMetadata;
    return meta?['display_name'] as String? ??
        widget.user.email?.split('@').first ??
        'Usuario';
  }

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
        _error =
            'El backend de análisis no está configurado. Define API_BASE_URL '
            'al ejecutar la app.';
        _status = WebViewStatus.error;
      });
      return;
    }

    try {
      // Resumen derivado de GET /api/v1/analyses (primera página, orden newest):
      // la respuesta trae `total` y el ítem más reciente.
      final page = await source.listAnalyses(limit: 1, offset: 0, sort: 'newest');
      if (!mounted) return;
      setState(() {
        _total = page.total;
        _last = page.items.isEmpty ? null : page.items.first;
        _status = _total == 0 ? WebViewStatus.empty : WebViewStatus.content;
      });
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
        _error = 'No se pudo cargar el historial. Inténtalo de nuevo.';
        _status = WebViewStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final last = _last;
    final total = _total;

    return WebPageScaffold(
      title: 'Inicio',
      status: _status,
      loadingBuilder: (_) => const HomeSkeleton(),
      onRetry: _load,
      emptyTitle: 'Aún no tienes análisis',
      emptyHint: 'Cuando realices un análisis, aparecerá un resumen aquí.',
      emptyActionLabel: 'Ver historial',
      onEmptyAction: widget.onOpenHistory,
      errorMessage: _error ?? 'No se pudo cargar el historial.',
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      contentBuilder: (_) => ListView(
        children: [
          // ── Saludo ────────────────────────────────────────────────────
          Text(
            'Hola, $_displayName',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Este es el resumen de tu actividad en Nerilum.',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // ── Tarjetas de resumen: total + último análisis ───────────────
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.insights_outlined,
                  label: 'Total de análisis',
                  value: '$total',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.access_time_outlined,
                  label: 'Último análisis',
                  value: last == null ? '—' : _shortDate(last.createdAt),
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Último análisis (detalle breve) ───────────────────────────
          if (last != null) ...[
            const Text(
              'Último análisis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _LastAnalysisTile(
              result: last,
              onTap: () => widget.onOpenAnalysis(last.id ?? ''),
              colors: colors,
            ),
            const SizedBox(height: 20),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                'Todavía no hay análisis para mostrar.',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),

          const SizedBox(height: 20),

          // ── Acceso al historial ────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: widget.onOpenHistory,
            icon: const Icon(Icons.history),
            label: const Text('Ir al historial'),
          ),

          const SizedBox(height: 28),
          const _DisclaimerRow(),
        ],
      ),
    );
  }

  String _shortDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.mintSecondary, size: 22),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LastAnalysisTile extends StatelessWidget {
  const _LastAnalysisTile({
    required this.result,
    required this.onTap,
    required this.colors,
  });

  final AnalysisResult result;
  final VoidCallback onTap;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.displayName ?? 'Análisis sin nombre',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Categoría del modelo: ${result.category}',
                      style: TextStyle(
                        color: colors.mintSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclaimerRow extends StatelessWidget {
  const _DisclaimerRow();

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
