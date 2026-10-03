import '../models/appearance.dart';

abstract class AppearanceRepository {
  Future<AppAppearance> load();
  Future<void> save(AppAppearance appearance);
}
