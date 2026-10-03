import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/history_sort.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/history_sort_control.dart';
import '../widgets/main_components.dart';
import 'analysis_view.dart';
import 'home_view.dart';
import 'profile_view.dart';

// La vista coordina navegación; el estado y los casos de uso viven en MainViewModel.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  Future<void> _changeSort(BuildContext context, HistorySort value) async {
    final saved = await AppScope.of(context).mainViewModel
        .setHistorySort(value);
    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el orden. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  void _history(BuildContext context) {
    final model = AppScope.of(context).mainViewModel;
    model.refreshHistory();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InfoPage(
          title: 'Historial completo',
          child: AnimatedBuilder(
            animation: model,
            builder: (context, child) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HistorySortControl(
                  value: model.historySort,
                  onChanged: (sort) => _changeSort(context, sort),
                ),
                if (model.analyses.any((record) => record.isDemo)) ...[
                  const SizedBox(height: 8),
                  const DemoHistoryNotice(),
                ],
                const SizedBox(height: 20),
                if (model.analyses.isEmpty)
                  EmptyHistory(
                    onSelect: () {
                      Navigator.of(context).pop();
                      model.selectFromHome();
                    },
                  )
                else
                  for (final record in model.analyses) ...[
                    ResultCard(
                      result: record,
                      onTap: () => _openAnalysis(context, record),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAnalysis(BuildContext context, AnalysisResult result) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InfoPage(
          title: 'Detalle del análisis',
          child: Column(
            children: [
              ResultCard(result: result, onTap: null),
              const SizedBox(height: 20),
              if (result.isDemo) ...[
                const DemoHistoryNotice(),
                const SizedBox(height: 16),
              ],
              Text(
                result.isDemo
                    ? 'Categoría simulada: ${result.category}'
                    : 'Categoría del modelo: ${result.category}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Resultado orientativo. No constituye un diagnóstico médico.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final logout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta de demostración?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (logout == true && context.mounted) {
      await AppScope.of(context).mainViewModel.logout();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context).mainViewModel;
    return AnimatedBuilder(
      animation: model,
      builder: (context, child) => Scaffold(
        body: BrandBackdrop(
          child: SafeArea(
            bottom: false,
            child: switch (model.tab) {
              0 => HomeView(
                onProfile: () => model.selectTab(2),
                onSelectImage: model.selectFromHome,
                onHistory: () => _history(context),
                analyses: model.analyses,
                historySort: model.historySort,
                onSortChanged: (sort) => _changeSort(context, sort),
                onOpenAnalysis: (record) => _openAnalysis(context, record),
              ),
              1 => AnalysisView(
                image: model.image,
                result: model.result,
                error: model.error,
                processing: model.processing,
                onBack: () => model.selectTab(0),
                onPick: model.pickImage,
                onRemove: model.removeImage,
                onAnalyze: model.analyze,
              ),
              _ => ProfileView(
                account: model.account,
                onHistory: () => _history(context),
                onLogout: () => _confirmLogout(context),
              ),
            },
          ),
        ),
        bottomNavigationBar: _MainBottomBar(
          selected: model.tab,
          onSelect: model.selectTab,
        ),
      ),
    );
  }
}

class _MainBottomBar extends StatelessWidget {
  const _MainBottomBar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Container(
      color: colors.background,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(42),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  _item(0, Icons.home_outlined, 'Inicio', colors),
                  Expanded(
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Analizar: seleccionar una imagen',
                        child: InkWell(
                          onTap: () => onSelect(1),
                          borderRadius: BorderRadius.circular(40),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: colors.mint,
                              shape: BoxShape.circle,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  color: colors.mintDarkText,
                                ),
                                Text(
                                  'Analizar',
                                  style: TextStyle(
                                    color: colors.mintDarkText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _item(2, Icons.person_outline, 'Perfil', colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int tab, IconData icon, String label, NerilumPalette colors) =>
      Expanded(
        child: InkWell(
          onTap: () => onSelect(tab),
          borderRadius: BorderRadius.circular(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected == tab ? colors.mint : colors.textPrimary,
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected == tab ? colors.mint : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
}
