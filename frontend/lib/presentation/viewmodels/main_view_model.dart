import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/account.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/analysis_preview.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/models/history_sort.dart';
import '../../domain/models/pending_analysis.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/image_repository.dart';
import '../../domain/usecases/account_use_cases.dart';
import '../../domain/usecases/analysis_use_cases.dart';
import '../../domain/usecases/pending_use_cases.dart';
import '../../domain/usecases/preview_use_cases.dart';
import '../../domain/usecases/image_use_cases.dart';
import '../../domain/usecases/history_sort_use_cases.dart';

class MainViewModel extends ChangeNotifier {
  MainViewModel({
    required this.selectImage,
    required this.analyzeImage,
    this.previewImage,
    this.saveAnalysis,
    required this.loadHistory,
    required this.loadHistorySort,
    required this.saveHistorySort,
    required this.sortHistory,
    required this.currentAccount,
    required this.logoutAccount,
    this.onLogout,
    this.lookupAnalysis,
    // UseCases de pendientes — todos opcionales para conservar compatibilidad
    // con modos sin cola (mock sin Android, web).
    this.listPending,
    this.enqueuePending,
    this.findPending,
    this.getPendingImage,
    this.discardPending,
    this.beginPendingSave,
    this.completePendingSave,
    this.releaseExpiredPendingSave,
  });

  final SelectImage selectImage;
  final AnalyzeImage analyzeImage;
  final PreviewImage? previewImage;
  final SaveAnalysis? saveAnalysis;
  final LoadHistory loadHistory;
  final LoadHistorySort loadHistorySort;
  final SaveHistorySort saveHistorySort;
  final SortHistory sortHistory;
  final CurrentAccount currentAccount;
  final LogoutAccount logoutAccount;
  final VoidCallback? onLogout;
  final AnalysisLookupRepository? lookupAnalysis;

  // UseCases de análisis pendientes.
  final ListPending? listPending;
  final EnqueuePending? enqueuePending;
  final FindPending? findPending;
  final GetPendingImage? getPendingImage;
  final DiscardPending? discardPending;
  final BeginPendingSave? beginPendingSave;
  final CompletePendingSave? completePendingSave;
  final ReleaseExpiredPendingSave? releaseExpiredPendingSave;

  bool get _hasPendingSupport =>
      listPending != null &&
      enqueuePending != null &&
      findPending != null &&
      getPendingImage != null &&
      discardPending != null &&
      beginPendingSave != null &&
      completePendingSave != null &&
      releaseExpiredPendingSave != null;

  int tab = 0;
  SelectedImage? image;
  AnalysisResult? result;
  AnalysisPreview? preview;
  String? error;
  bool canQueueImage = false;
  String? pendingError;
  List<PendingAnalysis> pendingAnalyses = const [];
  String? activePendingId;
  bool _saveCommitted = false;
  bool get canEditPreviewName => !_saveCommitted && !saving;
  bool _enqueuing = false;
  final Set<String> _recoveringIds = {};
  bool processing = false;
  bool saving = false;
  bool picking = false;
  String analysisName = '';
  String? _operationKey;
  String? historyError;
  bool historyLoading = false;
  int _historyRequest = 0;
  List<AnalysisResult> _analyses = const [];
  HistorySort historySort = HistorySort.newest;
  bool _disposed = false;
  int _sessionVersion = 0;
  int _sortRevision = 0;
  Future<void> _sortWrites = Future<void>.value();
  final _sessionImages = <String, Uint8List>{};

  Uint8List? imageForRecord(String? id) =>
      id == null ? null : _sessionImages[id];

  void _rememberImage(String? id) {
    if (id == null || image == null) return;
    _sessionImages.remove(id);
    _sessionImages[id] = image!.bytes;
    while (_sessionImages.length > 3) {
      _sessionImages.remove(_sessionImages.keys.first);
    }
  }

  Account? get account => currentAccount();
  List<AnalysisResult> get analyses => sortHistory(_analyses, historySort);

  Future<void> restoreHistorySort() async {
    try {
      final saved = await loadHistorySort();
      if (_disposed) return;
      historySort = saved;
      notifyListeners();
    } catch (_) {
      // El orden predeterminado es el más reciente.
    }
  }

  Future<bool> setHistorySort(HistorySort value) async {
    if (historySort == value) return true;
    final previous = historySort;
    final revision = ++_sortRevision;
    historySort = value;
    notifyListeners();
    final pending = _sortWrites.then((_) => saveHistorySort(value));
    _sortWrites = pending.catchError((Object _) {});
    try {
      await pending;
      return true;
    } catch (_) {
      if (!_disposed && revision == _sortRevision) {
        historySort = previous;
        notifyListeners();
      }
      return false;
    }
  }

  void selectTab(int value) {
    tab = value;
    notifyListeners();
  }

  Future<void> selectFromHome() async {
    selectTab(1);
    await pickImage();
  }

  Future<void> pickImage() async {
    if (processing || saving || picking) return;
    final session = _sessionVersion;
    picking = true;
    try {
      final selected = await selectImage();
      if (_disposed || session != _sessionVersion || selected == null) return;
      tab = 1;
      image = selected;
      analysisName = '';
      _operationKey = null;
      result = null;
      preview = null;
      error = null;
      canQueueImage = false;
      notifyListeners();
    } on ImageSelectionFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      tab = 1;
      image = null;
      _operationKey = null;
      result = null;
      preview = null;
      error = failure.message;
      canQueueImage = false;
      notifyListeners();
    } finally {
      picking = false;
    }
  }

  void removeImage() {
    if (processing || saving) return;
    image = null;
    analysisName = '';
    _operationKey = null;
    result = null;
    preview = null;
    error = null;
    canQueueImage = false;
    notifyListeners();
  }

  Future<void> analyze() async {
    if (image == null ||
        processing ||
        saving ||
        result != null ||
        preview != null) {
      return;
    }
    final session = _sessionVersion;
    processing = true;
    error = null;
    canQueueImage = false;
    notifyListeners();
    try {
      if (previewImage != null) {
        final prepared = await previewImage!(image!);
        if (_disposed || session != _sessionVersion) return;
        preview = prepared;
      } else {
        _operationKey ??= const Uuid().v4();
        final analyzed = await analyzeImage(
          image!,
          displayName: analysisName.trim().isEmpty ? null : analysisName.trim(),
          idempotencyKey: _operationKey,
        );
        if (_disposed || session != _sessionVersion) return;
        result = analyzed;
        _rememberImage(analyzed.id);
        await refreshHistory();
      }
    } on AnalysisUnavailable catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } on AnalysisNetworkFailure {
      if (_disposed || session != _sessionVersion) return;
      canQueueImage = _hasPendingSupport;
      error = canQueueImage
          ? 'No se pudo completar la conexión. Inténtalo más tarde o guarda la imagen como pendiente.'
          : 'No se pudo completar la conexión. Inténtalo más tarde.';
    } on AnalysisFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } catch (_) {
      if (_disposed || session != _sessionVersion) return;
      error = 'No se pudo completar el análisis. Reintenta más adelante.';
    } finally {
      if (!_disposed && session == _sessionVersion) {
        processing = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadPending() async {
    final owner = account?.id;
    if (listPending == null || owner == null) return;
    final session = _sessionVersion;
    try {
      final records = await listPending!(owner);
      if (_disposed || session != _sessionVersion || account?.id != owner) {
        return;
      }
      pendingAnalyses = records;
      pendingError = null;
    } catch (_) {
      if (_disposed || session != _sessionVersion) return;
      pendingError = 'No se pudieron leer los pendientes cifrados.';
    }
    notifyListeners();
  }

  Future<bool> enqueueSelected() async {
    final owner = account?.id;
    final selected = image;
    if (!canQueueImage ||
        enqueuePending == null ||
        owner == null ||
        selected == null ||
        processing ||
        saving ||
        _enqueuing) {
      return false;
    }
    final session = _sessionVersion;
    _enqueuing = true;
    try {
      await enqueuePending!(owner, selected);
      if (_disposed || session != _sessionVersion || account?.id != owner) {
        return false;
      }
      removeImage();
      await loadPending();
      return true;
    } catch (_) {
      if (_disposed || session != _sessionVersion) return false;
      pendingError =
          'No se pudo guardar el pendiente cifrado. Comprueba el espacio disponible.';
      notifyListeners();
      return false;
    } finally {
      _enqueuing = false;
    }
  }

  Future<void> discardPendingById(String id) async {
    final owner = account?.id;
    if (owner == null || discardPending == null) return;
    try {
      await discardPending!(owner, id);
      await loadPending();
    } catch (_) {
      pendingError = 'No se pudo descartar el pendiente.';
      notifyListeners();
    }
  }

  Future<bool> previewPending(String id) async {
    final owner = account?.id;
    if (!_hasPendingSupport ||
        previewImage == null ||
        owner == null ||
        processing ||
        saving ||
        preview != null ||
        image != null) {
      return false;
    }
    final session = _sessionVersion;
    processing = true;
    pendingError = null;
    notifyListeners();
    try {
      final item = await findPending!(owner, id);
      if (item == null || item.status != 'pending') return false;
      final selected = await getPendingImage!(owner, id);
      final prepared = await previewImage!(selected);
      if (_disposed || session != _sessionVersion || account?.id != owner) {
        return false;
      }
      image = selected;
      preview = prepared;
      activePendingId = id;
      analysisName = '';
      _saveCommitted = false;
      notifyListeners();
      return true;
    } on AnalysisNetworkFailure {
      if (!_disposed && session == _sessionVersion) {
        pendingError =
            'Sin conexión. El pendiente sigue cifrado en este dispositivo.';
      }
      return false;
    } catch (_) {
      if (!_disposed && session == _sessionVersion) {
        pendingError =
            'No se pudo previsualizar el pendiente. Sigue guardado en el dispositivo.';
      }
      return false;
    } finally {
      if (!_disposed && session == _sessionVersion) {
        processing = false;
        notifyListeners();
      }
    }
  }

  Future<AnalysisResult?> resumePendingSave(String id) async {
    final owner = account?.id;
    if (owner == null ||
        !_hasPendingSupport ||
        lookupAnalysis == null ||
        !_recoveringIds.add(id)) {
      return null;
    }
    try {
      final item = await findPending!(owner, id);
      if (item == null ||
          item.status != 'saving' ||
          item.previewId == null ||
          item.saveProof == null ||
          item.displayName == null) {
        return null;
      }
      final found = await lookupAnalysis!.findById(item.previewId!);
      if (found != null) {
        await completePendingSave!(owner, id);
        await loadPending();
        await refreshHistory();
        return found;
      }
      if (account?.id != owner) return null;
      if (item.proofExpiresAt == null ||
          DateTime.now().toUtc().isAfter(item.proofExpiresAt!)) {
        await releaseExpiredPendingSave!(owner, id);
        await loadPending();
        pendingError =
            'El comprobante expiró. Vuelve a ver el resultado antes de guardarlo.';
        notifyListeners();
        return null;
      }
      // El resultado pudo haberse guardado aunque se perdiera la respuesta.
      // Reintentar exactamente el mismo comprobante y nombre evita duplicarlo.
      final prepared = AnalysisPreview(
        result: AnalysisResult(
          id: item.previewId,
          category: '',
          createdAt: item.createdAt,
        ),
        saveProof: item.saveProof!,
        expiresAt: item.proofExpiresAt!,
      );
      final selected = await pendingRepository!.image(owner, id);
      final saved = await saveAnalysis!(
        prepared,
        selected,
        displayName: item.displayName,
      );
      await completePendingSave!(owner, id);
      await loadPending();
      await refreshHistory();
      return saved;
    } finally {
      _recoveringIds.remove(id);
    }
  }

  Future<void> savePreview() async {
    if (preview == null ||
        image == null ||
        saveAnalysis == null ||
        saving ||
        processing) {
      return;
    }
    final session = _sessionVersion;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final name = analysisName.trim().isEmpty
          ? 'Análisis sin nombre'
          : analysisName.trim();
      final owner = account?.id;
      final localId = activePendingId;
      if (localId != null &&
          owner != null &&
          _hasPendingSupport &&
          !_saveCommitted) {
        await beginPendingSave!(
          owner,
          localId,
          previewId: preview!.result.id!,
          proof: preview!.saveProof,
          expiresAt: preview!.expiresAt,
          name: name,
        );
        _saveCommitted = true;
      }
      final saved = localId == null
          ? await saveAnalysis!(preview!, image!, displayName: name)
          : await resumePendingSave(localId);
      if (saved == null) {
        preview = null;
        image = null;
        activePendingId = null;
        _saveCommitted = false;
        return;
      }
      if (_disposed || session != _sessionVersion) return;
      result = saved;
      _rememberImage(saved.id);
      preview = null;
      activePendingId = null;
      _saveCommitted = false;
      if (localId == null) await refreshHistory();
    } on AnalysisUnavailable catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } on AnalysisFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } catch (_) {
      if (_disposed || session != _sessionVersion) return;
      error =
          'No se pudo guardar. Comprueba el historial antes de reintentar.';
    } finally {
      if (!_disposed && session == _sessionVersion) {
        saving = false;
        notifyListeners();
      }
    }
  }

  /// Comprueba si el preview activo sigue siendo válido y, si expiró,
  /// descarta el preview y reintenta obtenerlo desde el pendiente local.
  /// Retorna true si el preview es válido (o fue renovado) y false si falló.
  Future<bool> ensurePreviewValid(String localId) async {
    if (preview == null || activePendingId != localId) return false;
    if (!DateTime.now().toUtc().isAfter(preview!.expiresAt)) return true;
    // El preview expiró: descartar y reintentar.
    discardPreview();
    return previewPending(localId);
  }

  void discardPreview() {    if (saving || processing) return;
    preview = null;
    if (activePendingId != null) image = null;
    activePendingId = null;
    _saveCommitted = false;
    result = null;
    analysisName = '';
    error = null;
    notifyListeners();
  }

  Future<void> refreshHistory() async {
    final session = _sessionVersion;
    final request = ++_historyRequest;
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final records = await loadHistory();
      if (_disposed ||
          session != _sessionVersion ||
          request != _historyRequest) {
        return;
      }
      _analyses = records;
    } catch (failure) {
      if (_disposed ||
          session != _sessionVersion ||
          request != _historyRequest) {
        return;
      }
      historyError = switch (failure) {
        AnalysisFailure() => failure.message,
        AnalysisUnavailable() => failure.message,
        _ => 'No se pudo cargar el historial. Inténtalo de nuevo.',
      };
    } finally {
      if (!_disposed &&
          session == _sessionVersion &&
          request == _historyRequest) {
        historyLoading = false;
        notifyListeners();
      }
    }
  }

  void setAnalysisName(String value) {
    if (processing || saving || result != null || _saveCommitted) return;
    if (analysisName.trim() != value.trim()) {
      _operationKey = null;
      result = null;
    }
    analysisName = value;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await logoutAccount();
    } finally {
      clearSessionState();
      onLogout?.call();
    }
  }

  void clearSessionState() {
    _sessionVersion++;
    image = null;
    analysisName = '';
    _operationKey = null;
    _historyRequest++;
    historyLoading = false;
    historyError = null;
    result = null;
    preview = null;
    activePendingId = null;
    _saveCommitted = false;
    saving = false;
    _sessionImages.clear();
    error = null;
    canQueueImage = false;
    pendingError = null;
    pendingAnalyses = const [];
    _analyses = const [];
    tab = 0;
    processing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
