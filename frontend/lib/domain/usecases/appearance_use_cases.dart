import '../models/appearance.dart';
import '../repositories/appearance_repository.dart';

class LoadAppearance {
  const LoadAppearance(this.repository);
  final AppearanceRepository repository;
  Future<AppAppearance> call() => repository.load();
}

class SaveAppearance {
  const SaveAppearance(this.repository);
  final AppearanceRepository repository;
  Future<void> call(AppAppearance appearance) => repository.save(appearance);
}
