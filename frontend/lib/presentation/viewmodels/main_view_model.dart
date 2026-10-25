import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/account.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/analysis_preview.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/models/history_sort.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/image_repository.dart';
import '../../domain/usecases/account_use_cases.dart';
import '../../domain/usecases/analysis_use_cases.dart';
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

  int tab = 0;
  SelectedImage? image;
  AnalysisResult? result;
  AnalysisPreview? preview;
  String? error;
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
      notifyListeners();
    } on ImageSelectionFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      tab = 1;
      image = null;
      _operationKey = null;
      result = null;
      preview = null;
      error = failure.message;
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

  Future<void> savePreview() async {
    if (preview == null || saveAnalysis == null || saving || processing) return;
    final session = _sessionVersion;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final saved = await saveAnalysis!(
        preview!,
        displayName: analysisName.trim().isEmpty
            ? 'Análisis sin nombre'
            : analysisName.trim(),
      );
      if (_disposed || session != _sessionVersion) return;
      result = saved;
      _rememberImage(saved.id);
      preview = null;
      await refreshHistory();
    } on AnalysisUnavailable catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } on AnalysisFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      error = failure.message;
    } catch (_) {
      if (_disposed || session != _sessionVersion) return;
      error = 'No se pudo guardar. Comprueba el historial antes de reintentar.';
    } finally {
      if (!_disposed && session == _sessionVersion) {
        saving = false;
        notifyListeners();
      }
    }
  }

  void discardPreview() {
    if (saving || processing) return;
    preview = null;
    result = null;
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
    if (processing || saving || result != null) return;
    if (analysisName.trim() != value.trim()) {
      _operationKey = null;
      result = null;
    }
    analysisName = value;
    notifyListeners();
  }

  Future<void> logout() async {
    await logoutAccount();
    clearSessionState();
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
    saving = false;
    _sessionImages.clear();
    error = null;
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
