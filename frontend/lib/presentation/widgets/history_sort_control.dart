import 'package:flutter/material.dart';

import '../../domain/models/history_sort.dart';
import '../../core/theme/nerilum_theme.dart';

class HistorySortControl extends StatelessWidget {
  const HistorySortControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final HistorySort value;
  final ValueChanged<HistorySort> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Row(
      children: [
        Text(
          compact ? 'Orden:' : 'Ordenar:',
          style: TextStyle(color: colors.textSecondary),
        ),
        SizedBox(width: compact ? 6 : 12),
        Expanded(
          child: DropdownButton<HistorySort>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: compact
                ? const [
                    DropdownMenuItem(
                      value: HistorySort.newest,
                      child: Text('Recientes'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.oldest,
                      child: Text('Antiguos'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.nameAZ,
                      child: Text('Nombre A-Z'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.probability,
                      child: Text('Puntuación'),
                    ),
                  ]
                : const [
                    DropdownMenuItem(
                      value: HistorySort.newest,
                      child: Text('Más recientes'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.oldest,
                      child: Text('Más antiguos'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.nameAZ,
                      child: Text('Nombre A-Z'),
                    ),
                    DropdownMenuItem(
                      value: HistorySort.probability,
                      child: Text('Probabilidad'),
                    ),
                  ],
            onChanged: (chosen) {
              if (chosen != null) onChanged(chosen);
            },
          ),
        ),
      ],
    );
  }
}

class DemoHistoryNotice extends StatelessWidget {
  const DemoHistoryNotice({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Datos de ejemplo · Las probabilidades son simuladas y no tienen valor clínico.',
    style: TextStyle(
      fontSize: 13,
      color: NerilumPalette.of(context).textSecondary,
    ),
  );
}
