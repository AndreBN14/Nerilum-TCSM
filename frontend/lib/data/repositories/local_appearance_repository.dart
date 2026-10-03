import '../../domain/models/appearance.dart';
import '../../domain/repositories/appearance_repository.dart';
import '../datasources/local_appearance_data_source.dart';

class LocalAppearanceRepository implements AppearanceRepository {
  const LocalAppearanceRepository(this.source, {this.saveOverride});
  final LocalAppearanceDataSource source;
  final Future<void> Function(bool)? saveOverride;

  @override
  Future<AppAppearance> load() async =>
      await source.loadLightMode() ? AppAppearance.light : AppAppearance.dark;

  @override
  Future<void> save(AppAppearance appearance) =>
      (saveOverride ?? source.saveLightMode)(appearance == AppAppearance.light);
}
