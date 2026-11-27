import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/category_label.dart';
import '../../core/utils/score_text.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';
import '../widgets/web_date_range_modal.dart';

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

  // Ordenación por columna ('name' | 'date'); null respeta el orden del
  // backend (fecha descendente).
  String? _sortColumn;
  bool _sortAsc = true;

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
    if (_sortColumn != null) {
      int compare(AnalysisResult a, AnalysisResult b) {
        switch (_sortColumn) {
          case 'name':
            final an = (a.displayName ?? '').toLowerCase();
            final bn = (b.displayName ?? '').toLowerCase();
            return an.compareTo(bn);
          case 'probability':
            // Sin probabilidad (−1) queda al final en ambos sentidos.
            final ap = a.probability ?? -1.0;
            final bp = b.probability ?? -1.0;
            return ap.compareTo(bp);
          case 'date':
          default:
            return a.createdAt.compareTo(b.createdAt);
        }
      }

      list.sort(compare);
      if (!_sortAsc) {
        final reversed = list.reversed.toList();
        return _paginate(reversed);
      }
    }
    _paginate(list);
  }

  void _paginate(List<AnalysisResult> list) {
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

  bool get _hasActiveFilters => _categoryFilter != null || _dateFilter != null;

  /// Alterna la ordenación: primera pulsación ordena ascendente, las
  /// siguientes invierten. Cambiar de columna reinicia en ascendente,
  /// salvo Probabilidad, que arranca de mayor a menor (dirección natural
  /// para esa columna).
  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColumn = column;
        _sortAsc = column != 'probability';
      }
    });
    _page = 0;
    _apply();
  }

  /// Limpia ambos filtros (categoría y fechas) y vuelve a la primera página.
  /// Accesible desde el tacho de la barra de filtros y desde la acción del
  /// estado vacío.
  void _clearFilters() {
    setState(() {
      _categoryFilter = null;
      _dateFilter = null;
    });
    _page = 0;
    _apply();
  }

  Future<void> _pickDateRange() async {
    // Modal web centrado; el picker nativo de Material se muestra a
    // pantalla completa y desentona en el portal.
    final picked = await showWebDateRangeModal(context, initialRange: _dateFilter);
    if (picked != null) {
      setState(() => _dateFilter = picked);
      _page = 0;
      _apply();
    }
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
      emptyActionLabel: _hasActiveFilters ? 'Limpiar filtros' : null,
      onEmptyAction: _hasActiveFilters ? _clearFilters : null,
      errorMessage: _error ?? 'No se pudo cargar el historial.',
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      // Los filtros viven fuera del estado de la lista: si un filtro no
      // devuelve resultados, el usuario puede cambiarlos o limpiarlos.
      // El tacho, a la derecha, limpia ambos filtros de un toque.
      toolbar: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _FilterChip(
                  icon: Icons.calendar_month_outlined,
                  label: _dateFilter == null
                      ? 'Todas las fechas'
                      : _formatRange(_dateFilter!),
                  colors: colors,
                  onTap: _pickDateRange,
                  active: _dateFilter != null,
                ),
                // Menú anclado al chip: se abre debajo del filtro, no desde el
                // borde de la ventana (el bottom sheet era un patrón móvil).
                PopupMenuButton<String>(
                  initialValue: _categoryFilter ?? '',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  tooltip: 'Filtrar por categoría',
                  onSelected: (value) =>
                      _setCategory(value.isEmpty ? null : value),
                  color: colors.surface,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.border),
                  ),
                  itemBuilder: (_) => [
                    _categoryMenuItem('', 'Todas las categorías', colors),
                    for (final c in _categories)
                      _categoryMenuItem(c, categoryLabel(c), colors),
                  ],
                  child: _FilterChip(
                    icon: Icons.filter_list,
                    label: _categoryFilter == null
                        ? 'Todas las categorías'
                        : categoryLabel(_categoryFilter!),
                    colors: colors,
                    onTap: null, // El tap lo gestiona PopupMenuButton.
                    active: _categoryFilter != null,
                  ),
                ),
              ],
            ),
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 12),
            _ClearFiltersButton(colors: colors, onPressed: _clearFilters),
          ],
        ],
      ),
      contentBuilder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Tabla en escritorio; tarjetas en ventanas estrechas ────────
          // La paginación vive dentro del mismo bloque, pegada a la tabla:
          // en ventanas bajas la tabla cede altura (reserva de 60px) para
          // que ambos quepan sin overflow.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                Widget? pagination;
                if (_filteredTotal > 0) {
                  pagination = Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _PaginationBar(
                      page: _page,
                      pageSize: _pageSize,
                      total: _filteredTotal,
                      colors: colors,
                      onPage: (page) {
                        setState(() => _page = page);
                        _apply();
                      },
                    ),
                  );
                }
                if (constraints.maxWidth >= 640) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                constraints.maxHeight -
                                (pagination == null ? 0 : 60),
                          ),
                          child: _HistoryTable(
                            records: _records,
                            colors: colors,
                            sortColumn: _sortColumn,
                            sortAsc: _sortAsc,
                            onSort: _toggleSort,
                            onTap: (id) => widget.onOpenAnalysis(id),
                          ),
                        ),
                      ),
                      ?pagination,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    ?pagination,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const _DisclaimerRow(),
        ],
      ),
    );
  }

  /// Opción del menú de categorías; la activa lleva check y color mint.
  PopupMenuItem<String> _categoryMenuItem(
    String value,
    String label,
    NerilumPalette colors,
  ) {
    final selected = (_categoryFilter ?? '') == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: selected
                ? Icon(Icons.check, size: 18, color: colors.mint)
                : null,
          ),
          Text(
            label,
            style: TextStyle(
              color: selected ? colors.mint : null,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
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
  });

  final IconData icon;
  final String label;
  final NerilumPalette colors;
  // null cuando el tap lo gestiona un PopupMenuButton externo.
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? colors.surfaceRaised : colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: onTap == null
          ? _inner(colors)
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: _inner(colors),
            ),
    );
  }

  Widget _inner(NerilumPalette colors) {
    return Container(
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
          const SizedBox(width: 6),
          // Flecha: señal visual de que el chip abre un menú desplegable.
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: active ? colors.mint : colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Tacho para limpiar todos los filtros de un toque. Solo se muestra cuando
/// hay algún filtro activo.
class _ClearFiltersButton extends StatefulWidget {
  const _ClearFiltersButton({required this.colors, required this.onPressed});

  final NerilumPalette colors;
  final VoidCallback onPressed;

  @override
  State<_ClearFiltersButton> createState() => _ClearFiltersButtonState();
}

class _ClearFiltersButtonState extends State<_ClearFiltersButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Tooltip(
      message: 'Limpiar filtros',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hovering ? colors.surfaceRaised : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovering ? colors.error : colors.border,
              ),
            ),
            child: Icon(
              Icons.delete_outline,
              size: 20,
              color: _hovering ? colors.error : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabla de historial para ventanas anchas: cabecera ordenable
/// (Nombre/Probabilidad/Fecha) y filas con hover. En pantallas estrechas se
/// usa la versión en tarjetas ([_HistoryRow]).
class _HistoryTable extends StatelessWidget {
  const _HistoryTable({
    required this.records,
    required this.colors,
    required this.sortColumn,
    required this.sortAsc,
    required this.onSort,
    required this.onTap,
  });

  final List<AnalysisResult> records;
  final NerilumPalette colors;
  final String? sortColumn;
  final bool sortAsc;
  final void Function(String column) onSort;
  final ValueChanged<String> onTap;

  static const _categoryWidth = 200.0;
  static const _probabilityWidth = 110.0;
  static const _dateWidth = 150.0;
  static const _chevronWidth = 40.0;

  /// Altura fija de cada fila: hace la tabla uniforme y hace que la página
  /// (máx. 10 filas) determine el tamaño total del bloque.
  static const _rowHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      // Se ajusta al contenido: cabecera + filas de la página (máx. 10). Solo
      // si la ventana es muy baja, Flexible recorta y aparece scroll interno.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, thickness: 1, color: colors.border),
              itemBuilder: (_, index) {
                final item = records[index];
                return _HistoryTableRow(
                  result: item,
                  colors: colors,
                  onTap: () => onTap(item.id ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Celda de cabecera; si [column] no es null es ordenable.
  Widget _headCell(
    NerilumPalette colors, {
    required String label,
    required Widget child,
    String? column,
  }) {
    final active = sortColumn == column;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (column != null) ...[
          const SizedBox(width: 4),
          Icon(
            active
                ? (sortAsc ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 13,
            color: active ? colors.mint : colors.textSecondary.withValues(alpha: 0.4),
          ),
        ],
      ],
    );

    if (column == null) return content;

    return InkWell(
      onTap: () => onSort(column),
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }

  Widget _header() {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: colors.textSecondary,
    );
    return Container(
      color: colors.surfaceRaised,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _headCell(
              colors,
              label: 'Nombre',
              column: 'name',
              child: Text('NOMBRE', style: style),
            ),
          ),
          SizedBox(
            width: _categoryWidth,
            child: Text('CATEGORÍA', style: style),
          ),
          SizedBox(
            width: _probabilityWidth,
            child: _headCell(
              colors,
              label: 'Probabilidad',
              column: 'probability',
              child: Text('PROBABILIDAD', style: style),
            ),
          ),
          SizedBox(
            width: _dateWidth,
            child: _headCell(
              colors,
              label: 'Fecha',
              column: 'date',
              child: Text('FECHA', style: style),
            ),
          ),
          const SizedBox(width: _chevronWidth),
        ],
      ),
    );
  }
}

/// Fila de la tabla: celdas alineadas con la cabecera, hover y tap al detalle.
class _HistoryTableRow extends StatefulWidget {
  const _HistoryTableRow({
    required this.result,
    required this.colors,
    required this.onTap,
  });

  final AnalysisResult result;
  final NerilumPalette colors;
  final VoidCallback onTap;

  @override
  State<_HistoryTableRow> createState() => _HistoryTableRowState();
}

class _HistoryTableRowState extends State<_HistoryTableRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final d = widget.result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr =
        '${two(d.day)}/${two(d.month)}/${d.year} · '
        '${two(d.hour)}:${two(d.minute)}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering ? colors.surfaceRaised : colors.surface,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            height: _HistoryTable._rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.result.displayName ?? 'Análisis sin nombre',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: _HistoryTable._categoryWidth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          categoryLabel(widget.result.category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.mintSecondary,
                          ),
                        ),
                      ),
                      if (widget.result.isDemo) ...[
                        const SizedBox(width: 6),
                        Text(
                          'demo',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: _HistoryTable._probabilityWidth,
                  child: widget.result.probability == null
                      ? const SizedBox.shrink()
                      : Text(
                          scoreText(widget.result.probability!),
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                        ),
                ),
                SizedBox(
                  width: _HistoryTable._dateWidth,
                  child: Text(
                    dateStr,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
                const SizedBox(
                  width: _HistoryTable._chevronWidth,
                  child: Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.result,
    required this.colors,
    required this.onTap,
  });

  final AnalysisResult result;
  final NerilumPalette colors;
  final VoidCallback onTap;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // Feedback web: borde mint y fondo elevado al pasar el mouse.
    final borderColor = _hovering
        ? colors.mint.withValues(alpha: 0.55)
        : colors.border;
    String two(int n) => n.toString().padLeft(2, '0');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering ? colors.surfaceRaised : colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
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
                              '${two(widget.result.createdAt.day)}/'
                              '${two(widget.result.createdAt.month)}/'
                              '${widget.result.createdAt.year} · '
                              '${two(widget.result.createdAt.hour)}:'
                              '${two(widget.result.createdAt.minute)}',
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
                        widget.result.displayName ?? 'Análisis sin nombre',
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
                          Text(
                            categoryLabel(widget.result.category),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.mintSecondary,
                            ),
                          ),
                          if (widget.result.probability != null)
                            Text(
                              'Probabilidad: '
                              '${scoreText(widget.result.probability!)}',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          if (widget.result.isDemo)
                            Text(
                              'demo',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
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
      ),
    );
  }
}

/// Paginación numerada tipo portal web: ‹ [1] [2] [3] … [N] › con la página
/// activa resaltada y el rango visible ("11–20 de 43") a la derecha.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.colors,
    required this.onPage,
  });

  final int page;
  final int pageSize;
  final int total;
  final NerilumPalette colors;
  final ValueChanged<int> onPage;

  static const _buttonSize = 34.0;

  @override
  Widget build(BuildContext context) {
    final pageCount = (total + pageSize - 1) ~/ pageSize;
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = (page + 1) * pageSize > total ? total : (page + 1) * pageSize;

    // Ventana uniforme: 1 … [5 páginas alrededor de la actual] … N, con la
    // primera y la última siempre visibles y "…" en los huecos. Los límites
    // de la ventana (1..pageCount-6) evitan duplicar los extremos.
    final numbers = <int?>[];
    if (pageCount <= 7) {
      for (var i = 0; i < pageCount; i++) {
        numbers.add(i);
      }
    } else {
      final windowStart = (page - 2).clamp(1, pageCount - 6);
      final windowEnd = windowStart + 5; // exclusivo
      numbers.add(0);
      if (windowStart > 1) numbers.add(null);
      for (var i = windowStart; i < windowEnd; i++) {
        numbers.add(i);
      }
      if (windowEnd < pageCount - 1) numbers.add(null);
      numbers.add(pageCount - 1);
    }

    return Row(
      children: [
        IconButton(
          tooltip: 'Anterior',
          onPressed: page > 0 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        for (final n in numbers)
          n == null
              ? SizedBox(
                  width: _buttonSize,
                  height: _buttonSize,
                  child: Center(
                    child: Text(
                      '…',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : _PageButton(
                  label: '${n + 1}',
                  selected: n == page,
                  colors: colors,
                  onTap: n == page ? null : () => onPage(n),
                ),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: (page + 1) < pageCount ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const Spacer(),
        Text(
          '$from–$to de $total',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

/// Botón de número de página: activo relleno en mint, hover en surfaceRaised.
class _PageButton extends StatefulWidget {
  const _PageButton({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final NerilumPalette colors;
  final VoidCallback? onTap;

  @override
  State<_PageButton> createState() => _PageButtonState();
}

class _PageButtonState extends State<_PageButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: _PaginationBar._buttonSize,
            height: _PaginationBar._buttonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.mint
                  : _hovering
                      ? colors.surfaceRaised
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.selected ? colors.mint : colors.border,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                color: widget.selected
                    ? colors.mintDarkText
                    : colors.textSecondary,
              ),
            ),
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
