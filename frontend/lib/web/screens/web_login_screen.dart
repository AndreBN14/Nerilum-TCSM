import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';

/// Login / registro del portal web.
///
/// Datos necesarios: Supabase Auth.
///
/// Muestra dos modos:
///  - Iniciar sesión: correo + contraseña + "recuperar contraseña".
///  - Registrarse: nombre + correo + contraseña + aceptar términos.
///
/// Esqueleto: la estructura y validaciones visuales están listas. La llamada
/// real a Supabase Auth (`signInWithPassword` / `signUp` /
/// `resetPasswordForEmail`) se marca con TODO donde corresponde. El _AuthGate
/// de main_web.dart reacciona al stream de sesión y navega automáticamente
/// al portal.
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;
  bool _obscurePass = true;
  bool _acceptTerms = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isRegister && !_acceptTerms) {
      setState(() => _errorMessage = 'Debes aceptar los términos para continuar.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final client = Supabase.instance.client;
      if (_isRegister) {
        // TODO: registrar con Supabase Auth.
        await client.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          data: {'display_name': _nameCtrl.text.trim()},
        );
        if (mounted) {
          setState(() {
            _infoMessage =
                'Revisa tu correo para confirmar la cuenta antes de ingresar.';
            _isRegister = false;
          });
        }
      } else {
        // TODO: iniciar sesión con Supabase Auth.
        await client.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
        // El _AuthGate detecta la sesión y abre el portal automáticamente.
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.message));
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Error inesperado. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recoverPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Ingresa tu correo para recuperar la contraseña.');
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      // TODO: recuperar contraseña con Supabase Auth.
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _infoMessage = 'Te enviamos un correo para restablecer tu contraseña.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo enviar el correo. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Confirma tu correo antes de ingresar.';
    }
    if (lower.contains('too many requests')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    return raw;
  }

  void _toggleMode() => setState(() {
        _isRegister = !_isRegister;
        _errorMessage = null;
        _infoMessage = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NerilumColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/nerilum-logo-stacked.png',
                  height: 72,
                  errorBuilder: (_, _, _) => const Text(
                    'NERILUM',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NerilumColors.mint,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Portal web',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NerilumColors.textSecondary,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 40),
                _buildCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: NerilumColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NerilumColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isRegister ? 'Crear cuenta' : 'Ingresar',
              style: const TextStyle(
                color: NerilumColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isRegister
                  ? 'Regístrate para acceder al portal Nerilum.'
                  : 'Accede con tu cuenta Nerilum.',
              style: const TextStyle(
                color: NerilumColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // Nombre (solo registro)
            if (_isRegister) ...[
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: NerilumColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre.' : null,
              ),
              const SizedBox(height: 16),
            ],

            // Correo
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(color: NerilumColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa tu correo.';
                if (!v.contains('@')) return 'Correo inválido.';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Contraseña
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              autofillHints: const [AutofillHints.password],
              style: const TextStyle(color: NerilumColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Ingresa tu contraseña.' : null,
            ),

            // Aceptar términos (solo registro)
            if (_isRegister) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Switch(
                    value: _acceptTerms,
                    onChanged: (v) => setState(() => _acceptTerms = v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Acepto los términos y la política de privacidad.',
                      style: const TextStyle(
                        color: NerilumColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Recuperar contraseña (solo login)
            if (!_isRegister)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _recoverPassword,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),

            // Mensajes de info / error
            if (_infoMessage != null) ...[
              const SizedBox(height: 12),
              _MessageBanner(message: _infoMessage!, isError: false),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _MessageBanner(message: _errorMessage!, isError: true),
            ],

            const SizedBox(height: 24),

            // Acción principal
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: NerilumColors.mintDarkText,
                      ),
                    )
                  : Text(_isRegister ? 'Registrarme' : 'Ingresar'),
            ),

            const SizedBox(height: 16),

            // Conmutar entre login / registro
            Center(
              child: TextButton(
                onPressed: _loading ? null : _toggleMode,
                child: Text(
                  _isRegister
                      ? '¿Ya tienes cuenta? Inicia sesión'
                      : '¿No tienes cuenta? Regístrate',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? NerilumColors.error : NerilumColors.mint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
