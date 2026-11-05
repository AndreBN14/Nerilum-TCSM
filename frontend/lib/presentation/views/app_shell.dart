import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/pending_analysis.dart';
import '../viewmodels/main_view_model.dart';
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
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Timer? _retryTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _retryingPending = false;
  bool _noticeOpen = false;
  bool _appActive = true;
  final _notifiedPreviewIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPending();
    });
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncPending(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final availability = AppScope.of(context).networkAvailability;
    _connectivitySubscription ??= availability?.listen(
      (available) {
        if (available && _appActive) _syncPending();
      },
      onError: (Object error, StackTrace stackTrace) {
        // La comprobación al volver y el temporizador siguen disponibles.
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) _syncPending();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _syncPending() async {
    if (!mounted || _retryingPending || !_appActive) return;
    _retryingPending = true;
    try {
      final model = AppScope.of(context).mainViewModel;
      if (model.account == null ||
          model.pendingRepository == null ||
          model.processing ||
          model.saving) {
        return;
      }
      if (model.activePendingId != null && model.preview != null) {
        await _notifyPendingReady(model);
        return;
      }
      await model.loadPending();
      if (!mounted || model.account == null) return;
      for (final item in model.pendingAnalyses.where(
        (item) => item.status == 'saving',
      )) {
        try {
          await model.resumePendingSave(item.id);
        } catch (_) {
          // Sin red: conservar el comprobante para el siguiente intento.
        }
        if (!mounted) return;
      }
      if (model.preview != null || model.image != null || model.processing) {
        return;
      }
      for (final item in model.pendingAnalyses) {
        if (item.status != 'pending') continue;
        if (await model.previewPending(item.id)) {
          await _notifyPendingReady(model);
        }
        break; // Solo una previsualización a la vez.
      }
    } finally {
      _retryingPending = false;
    }
  }

  Future<void> _notifyPendingReady(MainViewModel model) async {
    final preview = model.preview;
    final localId = model.activePendingId;
    if (!mounted ||
        !_appActive ||
        _noticeOpen ||
        preview == null ||
        localId == null ||
        preview.result.id == null ||
        _notifiedPreviewIds.contains(preview.result.id)) {
      return;
    }
    final ownerId = model.account?.id;
    final previewId = preview.result.id!;
    _notifiedPreviewIds.add(previewId);
    _noticeOpen = true;
    try {
      final seeNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resultado listo'),
          content: const Text(
            'El resultado de la imagen pendiente está listo para revisar. '
            'No aparecerá en el historial hasta que decidas guardarlo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ver resultado'),
            ),
          ],
        ),
      );
      if (seeNow != true ||
          !mounted ||
          model.account?.id != ownerId ||
          model.activePendingId != localId ||
          model.preview?.result.id != previewId) {
        return;
      }
      if (DateTime.now().toUtc().isAfter(model.preview!.expiresAt)) {
        model.discardPreview();
        if (!await model.previewPending(localId)) {
          if (mounted) {
            _pendingMessage(
              'El resultado expiró. Toca el pendiente para reintentarlo.',
            );
          }
          return;
        }
      }
      if (mounted) _showPreview(context, model);
    } finally {
      _noticeOpen = false;
    }
  }

  void _pendingMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
    model.loadPending();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => AnimatedBuilder(
          animation: model,
          builder: (routeContext, _) => HistoryView(
            records: model.analyses,
            pending: model.pendingAnalyses,
            pendingError: model.pendingError,
            onDiscardPending: model.discardPending,
            onOpenPending: (item) => _openPending(routeContext, item),
            readyPendingId: model.preview == null
                ? null
                : model.activePendingId,
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
      _showPreview(context, model);
    } else if (model.result != null && model.previewImage == null) {
      final saved = model.result!;
      model.removeImage();
      _openAnalysis(context, saved);
    }
  }

  void _showPreview(BuildContext context, MainViewModel model) {
    if (model.activePendingId != null && model.preview?.result.id != null) {
      _notifiedPreviewIds.add(model.preview!.result.id!);
    }
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
  }

  Future<void> _openPending(BuildContext context, PendingAnalysis item) async {
    final model = AppScope.of(context).mainViewModel;
    if (item.status == 'saving') {
      try {
        final result = await model.resumePendingSave(item.id);
        if (context.mounted && result != null) _openAnalysis(context, result);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo comprobar el guardado. Reintenta cuando haya conexión.',
              ),
            ),
          );
        }
      }
      return;
    }
    if (model.activePendingId == item.id &&
        model.preview != null &&
        DateTime.now().toUtc().isAfter(model.preview!.expiresAt)) {
      model.discardPreview();
    }
    if (model.image != null && model.activePendingId != item.id) {
      _pendingMessage(
        'Quita o termina la imagen seleccionada antes de abrir el pendiente.',
      );
      return;
    }
    final ready =
        model.activePendingId == item.id && model.preview != null ||
        await model.previewPending(item.id);
    if (!context.mounted) return;
    if (ready) {
      _showPreview(context, model);
    } else {
      _pendingMessage(
        model.pendingError ??
            'No se pudo abrir el pendiente. Inténtalo de nuevo.',
      );
    }
  }

  Future<void> _offerQueue(BuildContext context) async {
    final model = AppScope.of(context).mainViewModel;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guardar para más tarde'),
        content: const Text(
          'La imagen se guardará cifrada en este dispositivo. Al recuperar la conexión '
          'podrás ver el resultado; no se añadirá al historial hasta que pulses Guardar. '
          'Puedes descartar la imagen pendiente en cualquier momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar pendiente'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      final saved = await model.enqueueSelected();
      if (context.mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagen pendiente guardada en este dispositivo.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final model = AppScope.of(context).mainViewModel;
    final logout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (logout != true || !context.mounted) return;
    if (model.pendingAnalyses.isNotEmpty) {
      final decision = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Imágenes pendientes'),
          content: const Text(
            '¿Quieres conservar tus imágenes pendientes cifradas en este dispositivo al cerrar sesión?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              child: const Text('Borrar pendientes'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'keep'),
              child: const Text('Conservar pendientes'),
            ),
          ],
        ),
      );
      if (!context.mounted || decision == null) return;
      if (decision == 'delete') {
        for (final item in List.of(model.pendingAnalyses)) {
          await model.discardPending(item.id);
        }
        if (!context.mounted) return;
        if (model.pendingAnalyses.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hay guardados pendientes que deben resolverse antes de borrarlos.',
              ),
            ),
          );
          return;
        }
      }
    }
    await model.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
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
                onQueue: model.canQueueImage
                    ? () => _offerQueue(context)
                    : null,
                pendingError: model.pendingError,
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
                  _item(1, Icons.camera_alt, 'Analizar', colors),
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
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: () => onSelect(tab),
            borderRadius: BorderRadius.circular(40),
            child: Center(
              child: selected == tab
                  ? Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: colors.mint,
                        shape: BoxShape.circle,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: colors.mintDarkText),
                          Text(
                            label,
                            style: TextStyle(
                              color: colors.mintDarkText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: colors.textPrimary),
                        Text(
                          label,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
}
