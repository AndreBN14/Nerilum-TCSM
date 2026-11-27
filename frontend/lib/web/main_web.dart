import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/api_configuration.dart';
import '../core/theme/nerilum_theme.dart';
import '../data/datasources/http_analysis_data_source.dart';
import '../domain/repositories/analysis_repository.dart';
import 'screens/web_login_screen.dart';
import 'screens/web_reset_password_screen.dart';
import 'web_portal_shell.dart';

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

  // El portal consume el backend de análisis si se define API_BASE_URL.
  // Sin él, las vistas que necesitan análisis muestran que el backend no está
  // configurado en lugar de fingir datos.
  const apiConfig = ApiConfiguration();
  HttpAnalysisDataSource? analysisSource;
  if (apiConfig.enabled) {
    try {
      final client = Supabase.instance.client;
      analysisSource = HttpAnalysisDataSource(
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
      );
    } catch (_) {
      // API_BASE_URL inválida: el portal sigue funcionando sin análisis.
      analysisSource = null;
    }
  }

  runApp(NerilumWebApp(analysisSource: analysisSource));
}

/// Tema web: extiende el tema oscuro de Nerilum con las superficies del
/// navegador que Flutter web todavía deja con valores por defecto: la barra
/// de desplazamiento y el color de selección de texto. Tematizarlas desde la
/// paleta es la señal más barata de que la página fue construida, no ensamblada.
ThemeData get _webTheme {
  final base = NerilumTheme.dark;
  return base.copyWith(
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return NerilumColors.mintSecondary;
        }
        if (states.contains(WidgetState.hovered)) {
          return NerilumColors.border.withValues(alpha: 0.9);
        }
        return NerilumColors.border.withValues(alpha: 0.55);
      }),
      trackColor: WidgetStateProperty.all(
        NerilumColors.surface.withValues(alpha: 0.4),
      ),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(10),
      crossAxisMargin: 2,
      mainAxisMargin: 4,
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: NerilumColors.mint.withValues(alpha: 0.28),
      cursorColor: NerilumColors.mint,
      selectionHandleColor: NerilumColors.mintSecondary,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

class NerilumWebApp extends StatelessWidget {
  const NerilumWebApp({super.key, this.analysisSource});

  final HttpAnalysisDataSource? analysisSource;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nerilum — Web',
      debugShowCheckedModeBanner: false,
      theme: _webTheme,
      home: _AuthGate(analysisSource: analysisSource),
    );
  }
}

/// ¿La sesión actual proviene del enlace de recuperación de contraseña?
///
/// Supabase marca la sesión generada por ese enlace dentro del JWT: el claim
/// `amr` (métodos de autenticación) incluye una entrada `recovery`. Leer la
/// marca es más fiable que esperar el evento `passwordRecovery`, que con el
/// flujo PKCE puede no emitirse. La regla oficial es la entrada con el
/// timestamp más reciente.
bool _isRecoverySession(Session session) {
  final parts = session.accessToken.split('.');
  if (parts.length < 2) return false;
  final dynamic payload;
  try {
    payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
  } catch (_) {
    return false;
  }
  final amr = payload['amr'];
  if (amr is! List || amr.isEmpty) return false;
  final entries = amr.whereType<Map>().toList()
    ..sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
  return entries.first['method'] == 'recovery';
}

/// Decide si mostrar login, recuperación o portal según la sesión activa.
class _AuthGate extends StatefulWidget {
  const _AuthGate({this.analysisSource});

  final HttpAnalysisDataSource? analysisSource;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  // Modo recuperación pegajoso: mientras la sesión provenga del enlace del
  // correo, el portal no muestra datos hasta que se defina la nueva
  // contraseña. Sin esto, cualquier evento posterior (p. ej. el refresco
  // automático del token) re-evaluaría el gate y pintaría el portal con
  // los datos del usuario dentro de una sesión de recuperación.
  bool _recoveryMode = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Mientras llega el primer evento revisamos la sesión local.
        final auth = Supabase.instance.client.auth;
        final session = auth.currentSession;
        final event = snapshot.data?.event;

        if (event == AuthChangeEvent.signedOut) {
          _recoveryMode = false;
          return const WebLoginScreen();
        }

        // Modo recuperación: por el evento o por la firma de la sesión.
        // Persiste hasta un signedOut (tras guardar la contraseña).
        final inRecovery = event == AuthChangeEvent.passwordRecovery ||
            (session != null && _isRecoverySession(session));
        _recoveryMode = inRecovery || _recoveryMode && session != null;

        if (_recoveryMode && session != null) {
          return WebResetPasswordScreen(user: session.user);
        }

        if (snapshot.hasData) {
          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.initialSession) {
            final user = snapshot.data!.session?.user;
            if (user != null) {
              return WebPortalShell(
                user: user,
                analysisSource: widget.analysisSource,
              );
            }
          }
        }

        // Sin evento aún: usar sesión persistida localmente.
        if (session != null) {
          return WebPortalShell(
            user: session.user,
            analysisSource: widget.analysisSource,
          );
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
      theme: _webTheme,
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
