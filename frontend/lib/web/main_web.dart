import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../app/api_configuration.dart';
import '../core/theme/nerilum_theme.dart';
import '../data/datasources/http_analysis_data_source.dart';
import '../domain/repositories/analysis_repository.dart';
import 'screens/web_email_verified_screen.dart';
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

const _authCallbackParams = {
  'code',
  'access_token',
  'refresh_token',
  'token_hash',
  'type',
  'error',
  'error_code',
  'error_description',
};

/// Parámetros del enlace con `token_hash` de las plantillas personalizadas
/// (recuperación o confirmación de registro), en query o fragmento.
({String tokenHash, String type})? _tokenHashCallback() {
  final uri = Uri.base;
  final fragmentParams = Uri.splitQueryString(uri.fragment);
  String? read(String key) =>
      uri.queryParameters[key] ?? fragmentParams[key];
  final tokenHash = read('token_hash');
  final type = read('type');
  if (tokenHash == null || type == null) return null;
  return (tokenHash: tokenHash, type: type);
}

/// URL viva del navegador.
///
/// Se lee directamente de `window.location.href` en lugar de `Uri.base`:
/// en Flutter web, `Uri.base` puede quedar desactualizado después del
/// `history.replaceState` que el SDK usa para limpiar la URL tras un canje
/// exitoso, lo que producía falsos "callback sin procesar".
Uri _liveUri() => Uri.parse(web.window.location.href);

/// ¿La URL actual trae parámetros de un callback de auth sin procesar?
///
/// Ocurre cuando el canje PKCE del enlace del correo falla (código ya usado
/// o verifier sobrescrito): el SDK lo registra en consola sin emitir evento
/// y la URL queda con `?code=`. Un callback fallido nunca debe aterrizar en
/// el portal con la sesión previa del navegador.
bool _hasUnprocessedAuthCallback() {
  final uri = _liveUri();
  final fragmentParams = Uri.splitQueryString(uri.fragment);
  bool has(String key) =>
      uri.queryParameters.containsKey(key) || fragmentParams.containsKey(key);
  return _authCallbackParams.any(has);
}

/// Quita los parámetros de callback de auth de la URL (query y fragmento)
/// sin recargar la página.
void _cleanAuthCallbackParams() {
  final uri = _liveUri();
  final query = Map<String, String>.of(uri.queryParameters)
    ..removeWhere((key, _) => _authCallbackParams.contains(key));
  final fragmentParams = Map<String, String>.of(
        Uri.splitQueryString(uri.fragment),
      )
      ..removeWhere((key, _) => _authCallbackParams.contains(key));

  var url = '${uri.scheme}://${uri.authority}${uri.path}';
  if (query.isNotEmpty) {
    url += '?${Uri(queryParameters: query).query}';
  }
  if (fragmentParams.isNotEmpty) {
    url +=
        '#${fragmentParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
  }
  web.window.history.replaceState(null, '', url);
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

  // Callback de auth fallido (canje PKCE rechazado o enlace inválido):
  // obliga al login con un aviso en lugar del portal. Se libera al iniciar
  // sesión de nuevo.
  bool _failedCallback = false;
  String? _failedCallbackMessage;

  // Procesamiento del enlace `token_hash` de las plantillas personalizadas:
  // un solo intento por carga (el token_hash es de un solo uso).
  bool _tokenHashAttempted = false;
  bool _processingTokenHash = false;

  // Registro verificado vía enlace: pantalla de éxito antes del portal.
  bool _emailVerifiedPending = false;

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
          _failedCallback = false;
          _emailVerifiedPending = false;
          return const WebLoginScreen();
        }
        // Un login nuevo revalida todo: limpia el estado de callback fallido.
        if (event == AuthChangeEvent.signedIn) {
          _failedCallback = false;
        }

        // Enlace de plantilla personalizada: token_hash + type (recuperación
        // o confirmación de registro). verifyOTP no usa el verifier de PKCE,
        // por lo que pedir otro tipo de correo no invalida este enlace.
        final tokenHashCallback = _tokenHashCallback();
        if (tokenHashCallback != null && !_tokenHashAttempted) {
          _tokenHashAttempted = true;
          _processingTokenHash = true;
          _startTokenHashVerification(
            tokenHashCallback.tokenHash,
            tokenHashCallback.type,
          );
          return const _ProcessingScreen();
        }
        if (_processingTokenHash) {
          return const _ProcessingScreen();
        }

        // Callback sin procesar (canje del enlace fallido): nunca aterrizar
        // en el portal con la sesión previa del navegador. Se evalúa ANTES
        // del modo recuperación para que una sesión de recuperación vieja
        // no secuestre un enlace de otro flujo. Y se omite cuando el evento
        // actual marca un canje/login exitoso: un canje que terminó bien
        // no debe producir el aviso aunque queden restos en la URL.
        final authExchangeSucceeded = event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed;
        if (_hasUnprocessedAuthCallback()) {
          if (authExchangeSucceeded) {
            // Restos de URL obsoletos tras un canje exitoso: limpiar sin avisar.
            _cleanAuthCallbackParams();
          } else {
            _failedCallback = true;
            _failedCallbackMessage ??= 'Este enlace ya fue utilizado o ya no '
                'es válido. Si ya confirmaste tu cuenta, inicia sesión '
                'normalmente; si no, vuelve a solicitar el correo.';
            _cleanAuthCallbackParams();
          }
        }
        if (_failedCallback) {
          return WebLoginScreen(initialMessage: _failedCallbackMessage);
        }

        // Registro verificado vía enlace: pantalla de éxito antes del
        // portal. La sesión ya existe; solo falta que el usuario decida
        // continuar (o cierre la pestaña y vuelva más tarde).
        if (_emailVerifiedPending && session != null) {
          return WebEmailVerifiedScreen(
            email: session.user.email ?? '',
            onContinue: () => setState(() => _emailVerifiedPending = false),
          );
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

  /// Verifica el `token_hash` del enlace de plantilla personalizada.
  ///
  /// No usa el verifier de PKCE, por lo que pedir otro tipo de correo no
  /// invalida este enlace. El éxito emite `passwordRecovery` (recuperación)
  /// o `signedIn` (registro) y el stream reconstruye el gate; el fallo
  /// muestra el login con un mensaje específico del flujo.
  Future<void> _startTokenHashVerification(
    String tokenHash,
    String type,
  ) async {
    final otpType = switch (type) {
      'recovery' => OtpType.recovery,
      'signup' => OtpType.signup,
      _ => null,
    };
    try {
      if (otpType == null) {
        throw AuthException(
          'El enlace ya no es válido o ya fue utilizado. '
          'Vuelve a solicitarlo e inténtalo de nuevo.',
        );
      }
      await Supabase.instance.client.auth.verifyOTP(
        type: otpType,
        tokenHash: tokenHash,
      );
      if (!mounted) return;
      // El evento emitido reconstruye el gate con la sesión nueva.
      _cleanAuthCallbackParams();
      setState(() {
        _processingTokenHash = false;
        // Registro confirmado: pantalla de verificación exitosa antes del
        // portal. La recuperación va a la pantalla de restablecer por su
        // propio evento (passwordRecovery).
        _emailVerifiedPending = otpType == OtpType.signup;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      _cleanAuthCallbackParams();
      setState(() {
        _processingTokenHash = false;
        _failedCallback = true;
        _failedCallbackMessage = switch (type) {
          'recovery' => 'El enlace de recuperación ya no es válido. '
              'Solicita otro correo e inténtalo de nuevo.',
          'signup' => 'El enlace de confirmación de registro ya no es '
              'válido. Inicia sesión y reenvía el correo de confirmación.',
          _ => e.message,
        };
      });
    } catch (_) {
      if (!mounted) return;
      _cleanAuthCallbackParams();
      setState(() {
        _processingTokenHash = false;
        _failedCallback = true;
        _failedCallbackMessage =
            'No se pudo procesar el enlace. Inténtalo de nuevo.';
      });
    }
  }
}

/// Pantalla de transición mientras se procesa el enlace del correo.
class _ProcessingScreen extends StatelessWidget {
  const _ProcessingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: NerilumColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 16),
            Text(
              'Procesando enlace…',
              style: TextStyle(color: NerilumColors.textSecondary),
            ),
          ],
        ),
      ),
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
