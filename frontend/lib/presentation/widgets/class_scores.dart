import 'package:flutter/material.dart';

import '../../core/utils/category_label.dart';
import '../../core/utils/score_text.dart';
import '../../domain/models/analysis_result.dart';
import '../../core/theme/nerilum_theme.dart';

class ClassScores extends StatelessWidget {
  const ClassScores({super.key, required this.result});
  final AnalysisResult result;

  static const categories = [
    'NonDemented',
    'VeryMildDemented',
    'MildDemented',
    'ModerateDemented',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    if (!categories.every(result.scores.containsKey)) {
      return const Text(
        'Puntuaciones por clase no disponibles para este resultado.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Probabilidades por clase',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        Text(
          'Salidas del modelo; no son probabilidades clínicas.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          categoryLabel(category),
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Semantics(
                          label:
                              '${categoryLabel(category)}: ${scoreText(result.scores[category]!)}',
                          child: LinearProgressIndicator(
                            value: result.scores[category]!.clamp(0.0, 1.0),
                            minHeight: 14,
                            borderRadius: BorderRadius.circular(3),
                            color: category == result.category
                                ? colors.mint
                                : colors.mintSecondary,
                            backgroundColor: colors.surfaceRaised,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 63,
                        child: Text(
                          scoreText(result.scores[category]!),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
