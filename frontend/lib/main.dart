import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_dependencies.dart';
import 'app/auth_configuration.dart';
import 'app/api_configuration.dart';
import 'data/datasources/http_analysis_data_source.dart';
import 'data/repositories/http_analysis_repository.dart';
import 'data/datasources/supabase_account_data_source.dart';
import 'data/repositories/supabase_account_repository.dart';
import 'data/repositories/encrypted_pending_analysis_repository.dart';
import 'domain/repositories/analysis_repository.dart';
import 'app/app_scope.dart';
import 'domain/models/appearance.dart';
import 'domain/models/account.dart';
import 'presentation/views/auth_screen.dart';
import 'presentation/views/app_shell.dart';
import 'presentation/views/splash_screen.dart';
import 'presentation/views/welcome_screen.dart';
import 'core/theme/nerilum_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AuthConfiguration();
  const apiConfig = ApiConfiguration();
  AppDependencies dependencies;
  try {
    config.validate();
    apiConfig.validate(authMode: config.mode);
    if (config.isSupabase) {
      await Supabase.initialize(url: config.url, publishableKey: config.key);
      final client = Supabase.instance.client;
      final analysisSource = apiConfig.enabled
          ? HttpAnalysisDataSource(
              baseUri: apiConfig.baseUri,
              accessToken: () async {
                try {
                  var session = client.auth.currentSession;
                  if (session != null && session.isExpired) {
                    session = (await client.auth.refreshSession()).session;
                  }
                  return session?.accessToken;
                } on AuthRetryableFetchException {
                  throw const AnalysisNetworkFailure(
                    'Sin conexión para verificar la sesión.',
                  );
                }
              },
            )
          : null;
      final pendingSource =
          analysisSource != null &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android
          ? EncryptedPendingAnalysisRepository()
          : null;
      dependencies = AppDependencies(
        accounts: SupabaseAccountRepository(
          SupabaseAccountDataSource(Supabase.instance.client, config.redirect),
        ),
        analysis: analysisSource == null
            ? const UnconfiguredAnalysisRepository()
            : HttpAnalysisRepository(analysisSource),
        usesRemoteAnalysis: analysisSource != null,
        pendingAnalyses: pendingSource,
        onDispose: () {
          analysisSource?.close();
          if (pendingSource != null) unawaited(pendingSource.close());
        },
      );
    } else {
      dependencies = AppDependencies();
    }
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'No se pudo inicializar la app. Revisa AUTH_MODE, '
              'SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY y API_BASE_URL.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  await dependencies.restoreLocalState();
  runApp(NerilumApp(dependencies: dependencies, disposeDependencies: true));
  if (dependencies.usesRemoteAnalysis &&
      dependencies.accountRepository.currentAccount != null) {
    unawaited(dependencies.mainViewModel.refreshHistory());
  }
}

class NerilumApp extends StatefulWidget {
  const NerilumApp({
    super.key,
    this.dependencies,
    this.initialLightMode = false,
    this.saveLightMode,
    this.disposeDependencies = false,
  });

  final AppDependencies? dependencies;
  final bool initialLightMode;
  final Future<void> Function(bool)? saveLightMode;
  final bool disposeDependencies;

  @override
  State<NerilumApp> createState() => _NerilumAppState();
}

class _NerilumAppState extends State<NerilumApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Account?>? _sessionSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    var activeId = _dependencies.accountRepository.currentAccount?.id;
    if (_dependencies.sessionController.ownerId != activeId) {
      _dependencies.sessionController.restore(activeId);
    }
    if (_dependencies.accountRepository is SupabaseAccountRepository) {
      final auth =
          (_dependencies.accountRepository as SupabaseAccountRepository)
              .source
              .client
              .auth;
      _authSubscription = auth.onAuthStateChange.listen(
        (state) {
          if (!mounted) return;
          if ((state.event == AuthChangeEvent.signedIn ||
                  state.event == AuthChangeEvent.tokenRefreshed) &&
              state.session != null) {
            _dependencies.sessionController.markVerified(
              state.session!.user.id,
            );
          } else if (state.event == AuthChangeEvent.signedOut) {
            _dependencies.sessionController.signOut();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (mounted) _dependencies.sessionController.markUnverified();
        },
      );
    }
    _sessionSubscription = _dependencies.accountRepository.sessionChanges
        .listen(
          (account) {
            if (!mounted) return;
            if (account?.id == activeId) return;
            activeId = account?.id;
            if (account == null) {
              _dependencies.sessionController.signOut();
            } else if (_dependencies.sessionController.ownerId != account.id) {
              _dependencies.sessionController.restore(account.id);
            }
            if (account != null) {
              _dependencies.mainViewModel.clearSessionState();
              _dependencies.mainViewModel.refreshHistory();
              _dependencies.mainViewModel.loadPending();
              _navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/app',
                (_) => false,
              );
            } else {
              _dependencies.mainViewModel.clearSessionState();
              _navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/welcome',
                (_) => false,
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // Errores de red durante refresh no son un evento signedOut.
            // Conservar la sesión y los datos del propietario hasta recibir
            // un signedOut explícito del SDK.
          },
        );
  }

  late final AppDependencies _dependencies =
      widget.dependencies ??
      AppDependencies(
        initialAppearance: widget.initialLightMode
            ? AppAppearance.light
            : AppAppearance.dark,
        saveLightMode: widget.saveLightMode,
      );

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _authSubscription?.cancel();
    if (widget.dependencies == null || widget.disposeDependencies) {
      _dependencies.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: _dependencies,
      child: AnimatedBuilder(
        animation: _dependencies.appearanceViewModel,
        builder: (context, child) {
          final mode =
              _dependencies.appearanceViewModel.appearance == AppAppearance.dark
              ? ThemeMode.dark
              : ThemeMode.light;
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'Nerilum',
            debugShowCheckedModeBanner: false,
            darkTheme: NerilumTheme.dark,
            themeMode: mode,
            theme: NerilumTheme.light,
            themeAnimationDuration:
                WidgetsBinding
                    .instance
                    .platformDispatcher
                    .accessibilityFeatures
                    .disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 650),
            themeAnimationCurve: Curves.easeInOutCubic,
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: mode == ThemeMode.dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarColor: mode == ThemeMode.dark
                    ? NerilumPalette.dark.background
                    : NerilumPalette.light.background,
                systemNavigationBarIconBrightness: mode == ThemeMode.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: child!,
            ),
            initialRoute: '/splash',
            routes: {
              '/splash': (_) => const SplashScreen(),
              '/welcome': (_) => const WelcomeScreen(),
              '/login': (_) => const AuthScreen(mode: AuthMode.login),
              '/register': (_) => const AuthScreen(mode: AuthMode.register),
              '/app': (_) => const AppShell(),
            },
          );
        },
      ),
    );
  }
}
