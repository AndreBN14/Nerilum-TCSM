import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';

/// Pantalla de nueva contraseña tras el enlace del correo de recuperación.
///
/// El `_AuthGate` de `main_web.dart` la muestra cuando Supabase emite el
/// evento `passwordRecovery` (el enlace del correo aterriza en el portal
/// con el token en la URL). Guarda la nueva contraseña con `updateUser` y
/// devuelve al login.
class WebResetPasswordScreen extends StatefulWidget {
  const WebResetPasswordScreen({super.key, required this.user});

  final User user;

  @override
  State<WebResetPasswordScreen> createState() => _WebResetPasswordScreenState();
}

class _WebResetPasswordScreenState extends State<WebResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('password')) {
      return 'La contraseña es demasiado débil. Usa al menos 6 caracteres.';
    }
    if (lower.contains('session') || lower.contains('token')) {
      return 'El enlace ya no es válido. Solicita otro correo de recuperación.';
    }
    return raw;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passCtrl.text),
      );
      if (mounted) setState(() => _success = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e.message));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo actualizar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _backToLogin() async {
    // El _AuthGate reacciona al evento signedOut y muestra el login.
    await Supabase.instance.client.auth.signOut();
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
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: NerilumColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: NerilumColors.border),
              ),
              child: _success ? _successView() : _formView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Restablecer contraseña',
            style: TextStyle(
              color: NerilumColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.user.email ?? '',
            style: const TextStyle(
              color: NerilumColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),

          // Nueva contraseña
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(color: NerilumColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa la nueva contraseña.';
              if (v.length < 6) return 'Debe tener al menos 6 caracteres.';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirmación
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            style: const TextStyle(color: NerilumColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Confirmar contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Confirma la contraseña.' : null,
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(message: _error!, isError: true),
          ],

          const SizedBox(height: 24),
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
                : const Text('Guardar contraseña'),
          ),
        ],
      ),
    );
  }

  Widget _successView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: NerilumColors.mint,
          size: 44,
        ),
        const SizedBox(height: 12),
        const Text(
          'Contraseña actualizada',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NerilumColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu contraseña se cambió correctamente. Vuelve a iniciar sesión '
          'con la nueva.',
          textAlign: TextAlign.center,
          style: TextStyle(color: NerilumColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _backToLogin,
          child: const Text('Volver al inicio de sesión'),
        ),
      ],
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
