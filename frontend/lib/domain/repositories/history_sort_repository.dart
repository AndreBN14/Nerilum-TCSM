import '../models/history_sort.dart';

abstract class HistorySortRepository {
  Future<HistorySort> load();
  Future<void> save(HistorySort sort);
}
