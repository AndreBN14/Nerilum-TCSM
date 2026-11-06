import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/score_text.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';

/// Vista Historial del portal web.
///
/// Muestra: lista paginada con fecha, categoría principal y probabilidad.
/// Permite filtrar por fecha y por categoría.
///
/// Datos necesarios: `GET /api/v1/analyses` (el backend pagina con
/// limit/offset y ordena con `sort`). El portal descarga el historial y aplica
/// los filtros de categoría/fecha y la paginación en el cliente, igual que la
/// app móvil.
class WebHistoryScreen extends StatefulWidget {
  const WebHistoryScreen({
    super.key,
    required this.user,
    required this.onOpenAnalysis,
    this.analysisSource,
  });

  final User user;
  final HttpAnalysisDataSource? analysisSource;
  final ValueChanged<String> onOpenAnalysis;

  @override
  State<WebHistoryScreen> createState() => _WebHistoryScreenState();
}

class _WebHistoryScreenState extends State<WebHistoryScreen> {
  static const _categories = [
    'NonDemented',
    'VeryMildDemented',
    'MildDemented',
    'ModerateDemented',
  ];

  static const _pageSize = 10;

  // Todo el historial descargado del backend.
  List<AnalysisResult> _all = const [];
  // Recuento tras filtrar (alimenta la barra de paginación) y página visible.
  int _filteredTotal = 0;
  List<AnalysisResult> _records = const [];
  int _page = 0;

  String? _categoryFilter;
  DateTimeRange? _dateFilter;

  WebViewStatus _status = WebViewStatus.loading;
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
        _error = 'El backend de análisis no está configurado. Define '
            'API_BASE_URL al ejecutar la app.';
        _status = WebViewStatus.error;
      });
      return;
    }

    try {
      // GET /api/v1/analyses (recorre las páginas como la app móvil).
      final records = await source.history();
      if (!mounted) return;
      _all = records;
      _page = 0;
      _apply();
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

  /// Aplica los filtros (categoría y rango de fecha) y la paginación en el
  /// cliente sobre [_all]. No consulta el backend de nuevo.
  void _apply() {
    Iterable<AnalysisResult> filtered = _all;
    if (_categoryFilter != null) {
      filtered = filtered.where((r) => r.category == _categoryFilter);
    }
    if (_dateFilter != null) {
      final s = _dateFilter!.start;
      final e = _dateFilter!.end;
      final start = DateTime(s.year, s.month, s.day);
      final end = DateTime(e.year, e.month, e.day, 23, 59, 59);
      filtered = filtered.where(
        (r) => !r.createdAt.isBefore(start) && !r.createdAt.isAfter(end),
      );
    }

    final list = filtered.toList();
    var page = _page;
    if (page * _pageSize > list.length) page = 0;
    final from = (page * _pageSize).clamp(0, list.length);
    final to = (from + _pageSize).clamp(0, list.length);
    _page = page;
    _records = list.sublist(from, to);
    _filteredTotal = list.length;
    setState(() {
      _status = _filteredTotal == 0 ? WebViewStatus.empty : WebViewStatus.content;
    });
  }

  void _setCategory(String? value) {
    setState(() => _categoryFilter = value);
    _page = 0;
    _apply();
  }

  void _clearCategory() => _setCategory(null);

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dateFilter,
    );
    if (picked != null) {
      setState(() => _dateFilter = picked);
      _page = 0;
      _apply();
    }
  }

  void _clearDate() {
    setState(() => _dateFilter = null);
    _page = 0;
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return WebPageScaffold(
      title: 'Historial',
      status: _status,
      loadingBuilder: (_) => const HistorySkeleton(),
      onRetry: _load,
      emptyTitle: 'Aún no tienes análisis',
      emptyHint: _categoryFilter == null && _dateFilter == null
          ? 'Cuando realices un análisis aparecerá en esta lista.'
          : 'Ningún análisis coincide con los filtros seleccionados.',
      errorMessage: _error ?? 'No se pudo cargar el historial.',
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      contentBuilder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Filtros: categoría + rango de fecha ────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _FilterChip(
                icon: Icons.filter_list,
                label: _categoryFilter ?? 'Todas las categorías',
                colors: colors,
                onTap: () => _showCategoryPicker(context),
                active: _categoryFilter != null,
                onClear: _categoryFilter == null ? null : _clearCategory,
              ),
              _FilterChip(
                icon: Icons.calendar_month_outlined,
                label: _dateFilter == null
                    ? 'Todas las fechas'
                    : _formatRange(_dateFilter!),
                colors: colors,
                onTap: _pickDateRange,
                active: _dateFilter != null,
                onClear: _dateFilter == null ? null : _clearDate,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Lista de registros (página visible) ────────────────────────
          Expanded(
            child: ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final item = _records[index];
                return _HistoryRow(
                  result: item,
                  colors: colors,
                  onTap: () => widget.onOpenAnalysis(item.id ?? ''),
                );
              },
            ),
          ),
          if (_filteredTotal > 0) ...[
            const SizedBox(height: 16),
            _PaginationBar(
              page: _page,
              pageSize: _pageSize,
              total: _filteredTotal,
              colors: colors,
              onPrev: _page > 0
                  ? () {
                      setState(() => _page--);
                      _apply();
                    }
                  : null,
              onNext: (_page + 1) * _pageSize < _filteredTotal
                  ? () {
                      setState(() => _page++);
                      _apply();
                    }
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          const _DisclaimerRow(),
        ],
      ),
    );
  }

  void _showCategoryPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Todas las categorías'),
              onTap: () {
                Navigator.pop(context);
                _setCategory(null);
              },
            ),
            for (final c in _categories)
              ListTile(
                title: Text(c),
                onTap: () {
                  Navigator.pop(context);
                  _setCategory(c);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatRange(DateTimeRange r) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(r.start.day)}/${two(r.start.month)}/${r.start.year} - '
        '${two(r.end.day)}/${two(r.end.month)}/${r.end.year}';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    required this.active,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final NerilumPalette colors;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? colors.surfaceRaised : colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? colors.mint : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
              if (onClear != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close, size: 16, color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.result,
    required this.colors,
    required this.onTap,
  });

  final AnalysisResult result;
  final NerilumPalette colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 15, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${two(d.day)}/${two(d.month)}/${d.year} · '
                            '${two(d.hour)}:${two(d.minute)}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result.displayName ?? 'Análisis sin nombre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Tag(label: result.category, colors: colors),
                        if (result.probability != null)
                          Text(
                            'Probabilidad: ${scoreText(result.probability!)}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        if (result.isDemo)
                          _Tag(
                            label: 'demo',
                            colors: colors,
                            outlined: true,
                          ),
                      ],
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.colors, this.outlined = false});

  final String label;
  final NerilumPalette colors;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlined ? colors.border : colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.colors,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pageSize;
  final int total;
  final NerilumPalette colors;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = (page + 1) * pageSize;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Text(
          '$from–${to > total ? total : to} de $total',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
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
