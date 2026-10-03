import 'package:shared_preferences/shared_preferences.dart';

class LocalHistorySortDataSource {
  LocalHistorySortDataSource({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync preferences;
  static const key = 'nerilum_history_sort';

  Future<String?> load() => preferences.getString(key);
  Future<void> save(String value) => preferences.setString(key, value);
}
