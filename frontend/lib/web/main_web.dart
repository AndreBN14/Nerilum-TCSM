import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/nerilum_theme.dart';
import 'screens/web_login_screen.dart';
import 'screens/web_home_screen.dart';

/// Entry point para la app web de prueba.
/// Ejecutar con:
///   flutter run -d chrome -t lib/web/main_web.dart \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_KEY=eyJ...
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);

  runApp(const NerilumWebApp());
}

class NerilumWebApp extends StatelessWidget {
  const NerilumWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nerilum — Web',
      debugShowCheckedModeBanner: false,
      theme: NerilumTheme.dark,
      home: const _AuthGate(),
    );
  }
}

/// Decide si mostrar login o home según la sesión activa.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Mientras llega el primer evento revisamos la sesión local.
        final session = Supabase.instance.client.auth.currentSession;

        if (snapshot.hasData) {
          final event = snapshot.data!.event;
          if (event == AuthChangeEvent.signedOut) {
            return const WebLoginScreen();
          }
          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.initialSession) {
            final user = snapshot.data!.session?.user;
            if (user != null) return WebHomeScreen(user: user);
          }
        }

        // Sin evento aún: usar sesión persistida localmente.
        if (session != null) {
          return WebHomeScreen(user: session.user);
        }

        return const WebLoginScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────
// App de error cuando faltan las dart-define
// ─────────────────────────────────────────────
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NerilumTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: NerilumColors.error, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Faltan variables de entorno',
                  style: TextStyle(
                    color: NerilumColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ejecuta la app con:\n\n'
                  'flutter run -d chrome -t lib/web/main_web.dart \\\n'
                  '  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \\\n'
                  '  --dart-define=SUPABASE_KEY=eyJ...',
                  style: TextStyle(
                    color: NerilumColors.textSecondary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
