import '../../domain/models/history_sort.dart';
import '../../domain/repositories/history_sort_repository.dart';
import '../datasources/local_history_sort_data_source.dart';

class LocalHistorySortRepository implements HistorySortRepository {
  const LocalHistorySortRepository(this.source);
  final LocalHistorySortDataSource source;

  @override
  Future<HistorySort> load() async {
    final saved = await source.load();
    for (final sort in HistorySort.values) {
      if (sort.name == saved) return sort;
    }
    return HistorySort.newest;
  }

  @override
  Future<void> save(HistorySort sort) => source.save(sort.name);
}
