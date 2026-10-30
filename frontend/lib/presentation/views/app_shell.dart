import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/history_sort.dart';
import '../../core/theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';
import 'analysis_view.dart';
import 'history_view.dart';
import 'report_detail_page.dart';
import 'preview_result_page.dart';
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
        builder: (routeContext) => AnimatedBuilder(
          animation: model,
          builder: (routeContext, _) => HistoryView(
            records: model.analyses,
            sort: model.historySort,
            onSortChanged: (sort) => _changeSort(routeContext, sort),
            loading: model.historyLoading,
            error: model.historyError,
            onRefresh: model.refreshHistory,
            onOpen: (record) => _openAnalysis(routeContext, record),
            onSelectImage: () {
              Navigator.pop(routeContext);
              model.selectFromHome();
            },
            onBack: () => Navigator.pop(routeContext),
            bottomBar: _MainBottomBar(
              selected: null,
              onSelect: (tab) {
                Navigator.pop(routeContext);
                model.selectTab(tab);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openAnalysis(BuildContext context, AnalysisResult result) {
    final model = AppScope.of(context).mainViewModel;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => ReportDetailPage(
          result: result,
          imageBytes: model.imageForRecord(result.id),
        ),
      ),
    );
  }

  Future<void> _analyze(BuildContext context) async {
    final model = AppScope.of(context).mainViewModel;
    await model.analyze();
    if (!context.mounted) return;
    if (model.preview != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PreviewResultPage(
            model: model,
            onSaved: (saved) {
              Navigator.of(context).pop();
              model.removeImage();
              _openAnalysis(context, saved);
            },
          ),
        ),
      );
    } else if (model.result != null && model.previewImage == null) {
      final saved = model.result!;
      model.removeImage();
      _openAnalysis(context, saved);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final logout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta?'),
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
                historyLoading: model.historyLoading,
                historyError: model.historyError,
                onRefreshHistory: model.refreshHistory,
                historySort: model.historySort,
                onSortChanged: (sort) => _changeSort(context, sort),
                onOpenAnalysis: (record) => _openAnalysis(context, record),
              ),
              1 => AnalysisView(
                image: model.image,
                error: model.error,
                processing: model.processing,
                onBack: () => model.selectTab(0),
                onPick: model.pickImage,
                onRemove: model.removeImage,
                onAnalyze: () => _analyze(context),
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
  final int? selected;
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
