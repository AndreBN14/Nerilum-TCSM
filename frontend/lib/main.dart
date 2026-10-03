import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/app_scope.dart';
import 'domain/models/appearance.dart';
import 'presentation/views/auth_screen.dart';
import 'presentation/views/app_shell.dart';
import 'presentation/views/splash_screen.dart';
import 'presentation/views/welcome_screen.dart';
import 'presentation/theme/nerilum_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = AppDependencies();
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
