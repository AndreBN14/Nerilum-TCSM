import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/mock_analysis_data_source.dart';

class MockAnalysisRepository implements AnalysisRepository {
  const MockAnalysisRepository(this.source, this.accounts);
  final MockAnalysisDataSource source;
  final AccountRepository accounts;

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) => source.analyze(image);

  @override
  Future<List<AnalysisResult>> history() =>
      source.history(accounts.isDemo ? accounts.currentAccount?.email : null);
}
