import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_dependencies.dart';
import 'app/auth_configuration.dart';
import 'data/datasources/supabase_account_data_source.dart';
import 'data/repositories/supabase_account_repository.dart';
import 'app/app_scope.dart';
import 'domain/models/appearance.dart';
import 'domain/models/account.dart';
import 'presentation/views/auth_screen.dart';
import 'presentation/views/app_shell.dart';
import 'presentation/views/splash_screen.dart';
import 'presentation/views/welcome_screen.dart';
import 'presentation/theme/nerilum_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AuthConfiguration();
  AppDependencies dependencies;
  try {
    config.validate();
    if (config.isSupabase) {
      await Supabase.initialize(url: config.url, publishableKey: config.key);
      dependencies = AppDependencies(
        accounts: SupabaseAccountRepository(
          SupabaseAccountDataSource(Supabase.instance.client, config.redirect),
        ),
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
              'No se pudo inicializar la autenticación. Revisa AUTH_MODE, '
              'SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  await dependencies.restoreLocalState();
  runApp(NerilumApp(dependencies: dependencies));
}

class NerilumApp extends StatefulWidget {
  const NerilumApp({
    super.key,
    this.dependencies,
    this.initialLightMode = false,
    this.saveLightMode,
  });

  final AppDependencies? dependencies;
  final bool initialLightMode;
  final Future<void> Function(bool)? saveLightMode;

  @override
  State<NerilumApp> createState() => _NerilumAppState();
}

class _NerilumAppState extends State<NerilumApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Account?>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    var activeEmail = _dependencies.accountRepository.currentAccount?.email;
    _sessionSubscription = _dependencies.accountRepository.sessionChanges
        .listen((account) {
          if (!mounted) return;
          if (account?.email == activeEmail) return;
          activeEmail = account?.email;
          if (account != null) {
            _dependencies.mainViewModel.refreshHistory();
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
        });
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
    if (widget.dependencies == null) _dependencies.dispose();
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
