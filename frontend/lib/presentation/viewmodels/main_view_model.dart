import 'package:flutter/foundation.dart';

import '../../domain/models/account.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/models/history_sort.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/image_repository.dart';
import '../../domain/usecases/account_use_cases.dart';
import '../../domain/usecases/analysis_use_cases.dart';
import '../../domain/usecases/image_use_cases.dart';
import '../../domain/usecases/history_sort_use_cases.dart';

class MainViewModel extends ChangeNotifier {
  MainViewModel({
    required this.selectImage,
    required this.analyzeImage,
    required this.loadHistory,
    required this.loadHistorySort,
    required this.saveHistorySort,
    required this.sortHistory,
    required this.currentAccount,
    required this.logoutAccount,
  });

  final SelectImage selectImage;
  final AnalyzeImage analyzeImage;
  final LoadHistory loadHistory;
  final LoadHistorySort loadHistorySort;
  final SaveHistorySort saveHistorySort;
  final SortHistory sortHistory;
  final CurrentAccount currentAccount;
  final LogoutAccount logoutAccount;

  int tab = 0;
  SelectedImage? image;
  AnalysisResult? result;
  String? error;
  bool processing = false;
  bool picking = false;
  List<AnalysisResult> _analyses = const [];
  HistorySort historySort = HistorySort.newest;
  bool _disposed = false;
  int _sessionVersion = 0;
  int _sortRevision = 0;
  Future<void> _sortWrites = Future<void>.value();

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
    if (processing || picking) return;
    final session = _sessionVersion;
    picking = true;
    try {
      final selected = await selectImage();
      if (_disposed || session != _sessionVersion || selected == null) return;
      tab = 1;
      image = selected;
      result = null;
      error = null;
      notifyListeners();
    } on ImageSelectionFailure catch (failure) {
      if (_disposed || session != _sessionVersion) return;
      tab = 1;
      image = null;
      result = null;
      error = failure.message;
      notifyListeners();
    } finally {
      picking = false;
    }
  }

  void removeImage() {
    if (processing) return;
    image = null;
    result = null;
    error = null;
    notifyListeners();
  }

  Future<void> analyze() async {
    if (image == null || processing) return;
    final session = _sessionVersion;
    processing = true;
    error = null;
    notifyListeners();
    try {
      final analyzed = await analyzeImage(image!);
      if (_disposed || session != _sessionVersion) return;
      result = analyzed;
      await refreshHistory();
    } on AnalysisUnavailable catch (failure) {
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

  Future<void> refreshHistory() async {
    final session = _sessionVersion;
    try {
      final records = await loadHistory();
      if (_disposed || session != _sessionVersion) return;
      _analyses = records;
      notifyListeners();
    } catch (_) {
      // El historial actual es opcional; no inventar registros si falla.
    }
  }

  Future<void> logout() async {
    _sessionVersion++;
    await logoutAccount();
    image = null;
    result = null;
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
