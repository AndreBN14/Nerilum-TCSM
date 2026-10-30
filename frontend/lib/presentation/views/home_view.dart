import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/history_sort.dart';
import '../../core/theme/nerilum_theme.dart';
import '../widgets/history_sort_control.dart';
import '../widgets/history_status.dart';
import '../widgets/main_components.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.onProfile,
    required this.onSelectImage,
    required this.onHistory,
    required this.analyses,
    required this.onOpenAnalysis,
    required this.historySort,
    required this.onSortChanged,
    required this.historyLoading,
    required this.historyError,
    required this.onRefreshHistory,
  });

  final VoidCallback onProfile;
  final VoidCallback onSelectImage;
  final VoidCallback onHistory;
  final List<AnalysisResult> analyses;
  final ValueChanged<AnalysisResult> onOpenAnalysis;
  final HistorySort historySort;
  final ValueChanged<HistorySort> onSortChanged;
  final bool historyLoading;
  final String? historyError;
  final VoidCallback onRefreshHistory;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return MainPageWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
        children: [
          Row(
            children: [
              Image.asset(
                'assets/nerilum-mark-512.png',
                width: 42,
                height: 42,
                color: Theme.of(context).brightness == Brightness.light
                    ? colors.mint
                    : null,
                colorBlendMode: BlendMode.srcIn,
              ),
              const SizedBox(width: 10),
              const Text('N E R I L U M', style: TextStyle(fontSize: 14)),
              const Spacer(),
              IconButton.outlined(
                tooltip: 'Mi perfil',
                onPressed: onProfile,
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          const SizedBox(height: 52),
          Text(
            'Explora imágenes\ncerebrales',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
          ),
          const SizedBox(height: 12),
          Text(
            'Análisis orientativo de imágenes MRI.',
            style: TextStyle(color: colors.textSecondary, fontSize: 17),
          ),
          const SizedBox(height: 28),
          MintButton(
            label: 'Seleccionar imagen',
            icon: Icons.image_outlined,
            onPressed: onSelectImage,
          ),
          const SizedBox(height: 44),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Análisis recientes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: onHistory,
                label: const Text('Ver todo'),
                icon: const Icon(Icons.arrow_forward, size: 18),
                iconAlignment: IconAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 12),
          HistorySortControl(value: historySort, onChanged: onSortChanged),
          if (analyses.any((record) => record.isDemo)) ...[
            const SizedBox(height: 6),
            const DemoHistoryNotice(),
          ],
          const SizedBox(height: 12),
          HistoryStatus(
            loading: historyLoading,
            error: historyError,
            onRetry: onRefreshHistory,
          ),
          if (analyses.isEmpty && !historyLoading && historyError == null)
            EmptyHistory(onSelect: onSelectImage)
          else if (analyses.isNotEmpty)
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: analyses.length,
                separatorBuilder: (_, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: 214,
                  child: ResultCard(
                    result: analyses[index],
                    onTap: () => onOpenAnalysis(analyses[index]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 30),
          const AnalysisDisclaimer(),
        ],
      ),
    );
  }
}
