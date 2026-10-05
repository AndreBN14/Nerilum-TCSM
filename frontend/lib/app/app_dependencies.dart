import '../data/datasources/local_appearance_data_source.dart';
import '../data/datasources/local_image_data_source.dart';
import '../data/datasources/local_history_sort_data_source.dart';
import '../data/datasources/mock_account_data_source.dart';
import '../data/datasources/mock_session_data_source.dart';
import '../data/datasources/mock_analysis_data_source.dart';
import '../data/repositories/local_appearance_repository.dart';
import '../data/repositories/local_image_repository.dart';
import '../data/repositories/local_history_sort_repository.dart';
import '../data/repositories/mock_account_repository.dart';
import '../data/repositories/mock_analysis_repository.dart';
import '../domain/models/appearance.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/analysis_repository.dart';
import '../domain/repositories/appearance_repository.dart';
import '../domain/repositories/image_repository.dart';
import '../domain/repositories/history_sort_repository.dart';
import '../domain/usecases/account_use_cases.dart';
import '../domain/usecases/analysis_use_cases.dart';
import '../domain/usecases/appearance_use_cases.dart';
import '../domain/usecases/image_use_cases.dart';
import '../domain/usecases/history_sort_use_cases.dart';
import '../presentation/viewmodels/appearance_view_model.dart';
import '../presentation/viewmodels/auth_view_model.dart';
import '../presentation/viewmodels/main_view_model.dart';

// Punto de composición: cambiar una implementación no cambia las vistas.
class AppDependencies {
  AppDependencies({
    AccountRepository? accounts,
    MockSessionDataSource? sessionStore,
    ImageRepository? images,
    AnalysisRepository? analysis,
    AppearanceRepository? settings,
    HistorySortRepository? historySort,
    AppAppearance initialAppearance = AppAppearance.dark,
    Future<void> Function(bool)? saveLightMode,
  }) {
    accountRepository =
        accounts ??
        MockAccountRepository(
          MockAccountDataSource(),
          sessionStore ?? LocalMockSessionDataSource(),
        );
    final imageRepository =
        images ?? const LocalImageRepository(LocalImageDataSource());
    final analysisRepository =
        analysis ??
        MockAnalysisRepository(
          const MockAnalysisDataSource(),
          accountRepository,
        );
    final sortRepository =
        historySort ?? LocalHistorySortRepository(LocalHistorySortDataSource());
    final appearanceRepository =
        settings ??
        LocalAppearanceRepository(
          const LocalAppearanceDataSource(),
          saveOverride: saveLightMode,
        );

    appearanceViewModel = AppearanceViewModel(
      loadAppearance: LoadAppearance(appearanceRepository),
      saveAppearance: SaveAppearance(appearanceRepository),
      appearance: initialAppearance,
    );
    mainViewModel = MainViewModel(
      selectImage: SelectImage(imageRepository),
      analyzeImage: AnalyzeImage(analysisRepository),
      loadHistory: LoadHistory(analysisRepository),
      loadHistorySort: LoadHistorySort(sortRepository),
      saveHistorySort: SaveHistorySort(sortRepository),
      sortHistory: const SortHistory(),
      currentAccount: CurrentAccount(accountRepository),
      logoutAccount: LogoutAccount(accountRepository),
    );
  }

  late final AccountRepository accountRepository;
  late final AppearanceViewModel appearanceViewModel;
  late final MainViewModel mainViewModel;

  Future<void> restoreLocalState() async {
    await appearanceViewModel.load();
    await mainViewModel.restoreHistorySort();
    try {
      await accountRepository.restoreSession();
    } catch (_) {
      // Si no se puede recuperar la sesión mock, se ofrece la bienvenida.
    }
    if (accountRepository.currentAccount != null) {
      await mainViewModel.refreshHistory();
    }
  }

  AuthViewModel createAuthViewModel() => AuthViewModel(
    loginAccount: LoginAccount(accountRepository),
    registerAccount: RegisterAccount(accountRepository),
    resendConfirmation: ResendConfirmation(accountRepository),
  );

  void dispose() {
    appearanceViewModel.dispose();
    mainViewModel.dispose();
  }
}
