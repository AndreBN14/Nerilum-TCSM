import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/history_sort.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/history_sort_control.dart';
import '../widgets/history_status.dart';
import '../widgets/main_components.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({
    super.key,
    required this.records,
    required this.sort,
    required this.onSortChanged,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
    required this.onSelectImage,
    required this.onBack,
    this.bottomBar,
  });

  final List<AnalysisResult> records;
  final HistorySort sort;
  final ValueChanged<HistorySort> onSortChanged;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<AnalysisResult> onOpen;
  final VoidCallback onSelectImage;
  final VoidCallback onBack;
  final Widget? bottomBar;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final _search = TextEditingController();
  bool _searching = false;
  String? _classFilter;

  static const _classes = [
    'NonDemented',
    'VeryMildDemented',
    'MildDemented',
    'ModerateDemented',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final visible = widget.records.where((item) {
      final name = item.displayName ?? 'Análisis sin nombre';
      return name.toLowerCase().contains(query) &&
          (_classFilter == null || item.category == _classFilter);
    }).toList();

    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          bottom: false,
          child: MainPageWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver a Inicio',
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Historial',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Buscar por nombre',
                      icon: const Icon(Icons.search),
                      onPressed: () => setState(() {
                        _searching = !_searching;
                        if (!_searching) _search.clear();
                      }),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Filtrar por clase',
                      icon: Icon(
                        Icons.filter_list,
                        color: _classFilter == null ? null : colors.mint,
                      ),
                      onSelected: (value) => setState(
                        () => _classFilter = value == 'all' ? null : value,
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'all',
                          child: Text('Todas las clases'),
                        ),
                        for (final category in _classes)
                          PopupMenuItem(value: category, child: Text(category)),
                      ],
                    ),
                  ],
                ),
                if (_searching) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Buscar por nombre',
                      suffixIcon: IconButton(
                        tooltip: 'Borrar búsqueda',
                        onPressed: () => setState(() => _search.clear()),
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                HistorySortControl(
                  value: widget.sort,
                  onChanged: widget.onSortChanged,
                ),
                if (widget.records.any((item) => item.isDemo)) ...[
                  const SizedBox(height: 8),
                  const DemoHistoryNotice(),
                ],
                const SizedBox(height: 12),
                HistoryStatus(
                  loading: widget.loading,
                  error: widget.error,
                  onRetry: widget.onRefresh,
                ),
                if (widget.records.isEmpty &&
                    !widget.loading &&
                    widget.error == null)
                  EmptyHistory(onSelect: widget.onSelectImage)
                else if (visible.isEmpty &&
                    !widget.loading &&
                    widget.error == null)
                  const Padding(
                    padding: EdgeInsets.all(22),
                    child: Text(
                      'No hay análisis que coincidan con la búsqueda o el filtro.',
                    ),
                  )
                else
                  for (final item in visible) ...[
                    _HistoryTile(
                      result: item,
                      onTap: () => widget.onOpen(item),
                    ),
                    const SizedBox(height: 12),
                  ],
                const AnalysisDisclaimer(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.bottomBar,
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.result, required this.onTap});
  final AnalysisResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final d = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${two(d.day)}/${two(d.month)}/${d.year} · '
                            '${two(d.hour)}:${two(d.minute)}',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      result.displayName ?? 'Análisis sin nombre',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Clase estimada:',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceRaised,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: colors.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              result.category,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
