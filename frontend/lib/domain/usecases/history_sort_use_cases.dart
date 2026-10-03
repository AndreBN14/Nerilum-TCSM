import '../models/analysis_result.dart';
import '../models/history_sort.dart';
import '../repositories/history_sort_repository.dart';

class LoadHistorySort {
  const LoadHistorySort(this.repository);
  final HistorySortRepository repository;
  Future<HistorySort> call() => repository.load();
}

class SaveHistorySort {
  const SaveHistorySort(this.repository);
  final HistorySortRepository repository;
  Future<void> call(HistorySort sort) => repository.save(sort);
}

class SortHistory {
  const SortHistory();

  List<AnalysisResult> call(List<AnalysisResult> records, HistorySort sort) {
    final sorted = List<AnalysisResult>.of(records);
    int byDate(AnalysisResult a, AnalysisResult b) =>
        b.createdAt.compareTo(a.createdAt);
    sorted.sort(
      (a, b) => switch (sort) {
        HistorySort.newest => byDate(a, b),
        HistorySort.oldest => -byDate(a, b),
        HistorySort.nameAZ => _byName(a, b, byDate),
        HistorySort.probability => _byProbability(a, b, byDate),
      },
    );
    return sorted;
  }

  int _byName(
    AnalysisResult a,
    AnalysisResult b,
    int Function(AnalysisResult, AnalysisResult) byDate,
  ) {
    final aName = a.displayName;
    final bName = b.displayName;
    if (aName == null) return bName == null ? byDate(a, b) : 1;
    if (bName == null) return -1;
    final order = aName.toLowerCase().compareTo(bName.toLowerCase());
    return order == 0 ? byDate(a, b) : order;
  }

  int _byProbability(
    AnalysisResult a,
    AnalysisResult b,
    int Function(AnalysisResult, AnalysisResult) byDate,
  ) {
    final aValue = a.probability;
    final bValue = b.probability;
    if (aValue == null) return bValue == null ? byDate(a, b) : 1;
    if (bValue == null) return -1;
    final order = bValue.compareTo(aValue);
    return order == 0 ? byDate(a, b) : order;
  }
}
