import 'package:flutter/material.dart';

import '../../core/theme/nerilum_theme.dart';
import '../widgets/web_dialogs.dart';

/// Modal de selección de rango de fechas del portal web.
///
/// Sustituye a `showDateRangePicker`, que Material muestra a pantalla
/// completa (usa el tamaño de la ventana como tamaño del diálogo). Aquí se
/// usa un diálogo centrado con calendario de rango propio y presets
/// rápidos, siguiendo el mismo lenguaje visual que el resto del portal.
Future<DateTimeRange?> showWebDateRangeModal(
  BuildContext context, {
  DateTimeRange? initialRange,
  int pastYears = 5,
}) {
  final now = DateTime.now();
  return showBlurDialog<DateTimeRange>(
    context: context,
    builder: (_) => _DateRangeModal(
      initialRange: initialRange,
      firstDate: DateTime(now.year - pastYears),
      lastDate: now,
    ),
  );
}

class _DateRangeModal extends StatefulWidget {
  const _DateRangeModal({
    required this.initialRange,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTimeRange? initialRange;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateRangeModal> createState() => _DateRangeModalState();
}

class _DateRangeModalState extends State<_DateRangeModal> {
  static const _monthsEs = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  static const _weekdaysEs = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  static const _cellSize = 38.0;

  DateTime? _start;
  DateTime? _end;
  // Primer mes visible en el calendario.
  late DateTime _firstVisibleMonth;
  DateTime get _today {
    final now = widget.lastDate;
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRange;
    if (initial != null) {
      _start = initial.start;
      _end = initial.end;
      _firstVisibleMonth = DateTime(
        initial.start.year,
        initial.start.month,
        1,
      );
    } else {
      final today = _today;
      _firstVisibleMonth = DateTime(today.year, today.month, 1);
    }
  }

  // ── Selección ──────────────────────────────────────────────────────────────
  void _tapDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (_start == null || (_start != null && _end != null)) {
      // Nueva selección.
      setState(() {
        _start = d;
        _end = null;
      });
      return;
    }
    if (!d.isAfter(_start!)) {
      // Antes del inicio: reinicia con este día como inicio.
      setState(() {
        _start = d;
        _end = null;
      });
    } else {
      setState(() => _end = d);
    }
  }

  void _applyPreset(DateTimeRange range) {
    Navigator.of(context).pop(DateTimeRange(start: range.start, end: range.end));
  }

  void _apply() {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return;
    Navigator.of(context).pop(DateTimeRange(start: start, end: end));
  }

  void _shiftMonths(int delta) {
    setState(() {
      _firstVisibleMonth = DateTime(
        _firstVisibleMonth.year,
        _firstVisibleMonth.month + delta,
        1,
      );
    });
  }

  bool _isDisabled(DateTime day) =>
      day.isBefore(DateTime(
        widget.firstDate.year,
        widget.firstDate.month,
        widget.firstDate.day,
      )) ||
      day.isAfter(_today);

  // ── Presets ────────────────────────────────────────────────────────────────
  List<(String, DateTimeRange)> _presets() {
    final today = _today;
    return [
      (
        'Últimos 7 días',
        DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      ),
      (
        'Últimos 30 días',
        DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
      ),
      (
        'Este mes',
        DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
      ),
    ];
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(colors),
              const SizedBox(height: 16),
              _presetsRow(colors),
              const SizedBox(height: 16),
              Flexible(child: _calendar(colors)),
              const SizedBox(height: 20),
              _actions(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(NerilumPalette colors) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Filtrar por fecha',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }

  Widget _presetsRow(NerilumPalette colors) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, range) in _presets())
          ActionChip(
            label: Text(label, style: const TextStyle(fontSize: 13)),
            backgroundColor: colors.surfaceRaised,
            side: BorderSide(color: colors.border),
            onPressed: () => _applyPreset(range),
          ),
      ],
    );
  }

  /// Uno o dos meses visibles según el ancho disponible del diálogo.
  Widget _calendar(NerilumPalette colors) {
    const monthWidth = _cellSize * 7;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoMonths = constraints.maxWidth >= monthWidth * 2 + 40;
        final canGoBack = !_firstVisibleMonth
            .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1));
        final nextMonth = DateTime(
          _firstVisibleMonth.year,
          _firstVisibleMonth.month + (twoMonths ? 2 : 1),
          1,
        );
        final canGoForward = !nextMonth.isAfter(DateTime(
          widget.lastDate.year,
          widget.lastDate.month,
          1,
        ));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: canGoBack ? () => _shiftMonths(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: canGoForward ? () => _shiftMonths(twoMonths ? 2 : 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _monthGrid(_firstVisibleMonth, colors),
                  if (twoMonths) ...[
                    const SizedBox(width: 40),
                    _monthGrid(
                      DateTime(
                        _firstVisibleMonth.year,
                        _firstVisibleMonth.month + 1,
                        1,
                      ),
                      colors,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _monthGrid(DateTime month, NerilumPalette colors) {
    // Lunes como primer día de la semana (formato ES).
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final offset = firstOfMonth.weekday - 1; // Lunes = 0 … Domingo = 6
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = _today;

    Widget cell(int? day) {
      if (day == null) return const SizedBox(width: _cellSize, height: _cellSize);
      final date = DateTime(month.year, month.month, day);
      final disabled = _isDisabled(date);
      final isStart = _start != null && _sameDay(date, _start!);
      final isEnd = _end != null && _sameDay(date, _end!);
      final isSelected = isStart || isEnd;
      final inRange = _start != null &&
          _end != null &&
          date.isAfter(_start!) &&
          date.isBefore(_end!);
      final isToday = _sameDay(date, today);

      Color background = Colors.transparent;
      if (isSelected) background = colors.mint;
      if (inRange) background = colors.mint.withValues(alpha: 0.18);

      final textStyle = TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: disabled
            ? colors.textSecondary.withValues(alpha: 0.35)
            : isSelected
                ? colors.mintDarkText
                : colors.textPrimary,
      );

      Widget content = Container(
        width: _cellSize,
        height: _cellSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: inRange ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: inRange ? BorderRadius.zero : null,
          border: isToday && !isSelected
              ? Border.all(color: colors.mint, width: 1.2)
              : null,
        ),
        child: Text('$day', style: textStyle),
      );

      if (disabled) return content;
      return InkWell(
        onTap: () => _tapDay(date),
        borderRadius: BorderRadius.circular(_cellSize / 2),
        child: content,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre del mes + año
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '${_monthsEs[month.month - 1]} ${month.year}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        // Cabecera de días de la semana
        Row(
          children: [
            for (final wd in _weekdaysEs)
              SizedBox(
                width: _cellSize,
                height: 24,
                child: Center(
                  child: Text(
                    wd,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Días
        for (var week = 0; week * 7 < offset + daysInMonth; week++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Builder(builder: (_) {
                  final index = week * 7 + col;
                  final day = index - offset + 1;
                  return cell(day >= 1 && day <= daysInMonth ? day : null);
                }),
            ],
          ),
      ],
    );
  }

  Widget _actions(NerilumPalette colors) {
    final ready = _start != null && _end != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            ready
                ? '${_formatDate(_start!)} → ${_formatDate(_end!)}'
                : 'Selecciona una fecha de inicio y una de fin.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: ready ? _apply : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.mint,
            foregroundColor: colors.mintDarkText,
            disabledBackgroundColor: colors.surfaceRaised,
            disabledForegroundColor: colors.textSecondary,
          ),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}
