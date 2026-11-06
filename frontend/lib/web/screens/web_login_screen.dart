import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // El _AuthGate reacciona al stream y navega automáticamente.
    } on AuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.message));
    } catch (_) {
      setState(() => _errorMessage = 'Error inesperado. Intenta de nuevo.');
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
                // ── Logo / título ──────────────────────────────────
                Image.asset(
                  'assets/nerilum-logo-stacked.png',
                  height: 72,
                  errorBuilder: (context2, err, stack) => const Text(
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

                // ── Tarjeta ────────────────────────────────────────
                Container(
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
                        const Text(
                          'Ingresar',
                          style: TextStyle(
                            color: NerilumColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Accede con tu cuenta Nerilum.',
                          style: TextStyle(
                            color: NerilumColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Email
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
                            if (v == null || v.trim().isEmpty) {
                              return 'Ingresa tu correo.';
                            }
                            if (!v.contains('@')) {
                              return 'Correo inválido.';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _login(),
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
                              onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass),
                              tooltip: _obscurePass
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Ingresa tu contraseña.';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _login(),
                        ),

                        // Error
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: NerilumColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      NerilumColors.error.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: NerilumColors.error, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                        color: NerilumColors.error,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Botón ingresar
                        ElevatedButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: NerilumColors.mintDarkText,
                                  ),
                                )
                              : const Text('Ingresar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
