import 'package:flutter/material.dart';

import '../../domain/models/history_sort.dart';
import '../theme/nerilum_theme.dart';

class HistorySortControl extends StatelessWidget {
  const HistorySortControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final HistorySort value;
  final ValueChanged<HistorySort> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Row(
      children: [
        Text('Ordenar:', style: TextStyle(color: colors.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<HistorySort>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: const [
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
