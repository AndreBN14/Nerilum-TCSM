import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../widgets/web_dialogs.dart';

/// Traduce los errores de Supabase Auth a mensajes claros para el usuario.
///
/// Compartida por el modal de recuperación, el login y "Cambiar contraseña"
/// de Mi cuenta, para que el usuario nunca vea el error crudo del backend.
String friendlyAuthError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('redirect') || lower.contains('allow list')) {
    return 'La URL de este portal no está permitida en Supabase '
        '(Authentication → URL Configuration → Redirect URLs).';
  }
  if (lower.contains('rate limit') || lower.contains('too many requests')) {
    return 'Demasiados intentos. Espera unos minutos antes de reintentar.';
  }
  if (lower.contains('invalid login credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (lower.contains('email not confirmed')) {
    return 'Confirma tu correo antes de ingresar.';
  }
  if (lower.contains('unable to validate email') ||
      lower.contains('invalid email')) {
    return 'El correo no es válido.';
  }
  if (lower.contains('password')) {
    return 'La contraseña es demasiado débil. Usa al menos 6 caracteres.';
  }
  if (lower.contains('session') || lower.contains('token')) {
    return 'El enlace ya no es válido. Solicita otro correo.';
  }
  return raw;
}

/// Modal "Recuperar contraseña" del portal web.
///
/// Flujo dedicado: campo de correo propio + envío del enlace de
/// recuperación con `redirectTo` hacia el portal. Al aterrizar, el
/// `_AuthGate` de main_web.dart detecta la sesión de recuperación y abre
/// la pantalla de nueva contraseña.
Future<void> showForgotPasswordDialog(BuildContext context) {
  return showBlurDialog<void>(
    context: context,
    builder: (_) => const _ForgotPasswordDialog(),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // El enlace del correo vuelve al propio portal (debe estar en la
      // lista blanca de Redirect URLs del dashboard de Supabase).
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailCtrl.text.trim(),
        redirectTo: Uri.base.removeFragment().toString(),
      );
      if (mounted) setState(() => _success = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e.message));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo enviar el correo. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NerilumColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: NerilumColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _success ? _successView() : _formView(),
        ),
      ),
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recuperar contraseña',
                  style: TextStyle(
                    color: NerilumColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Ingresa tu correo y te enviaremos un enlace para definir una '
            'contraseña nueva.',
            style: TextStyle(color: NerilumColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Banner(message: _error!, isError: true),
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
                : const Text('Enviar enlace'),
          ),
        ],
      ),
    );
  }

  Widget _successView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: NerilumColors.mint,
          size: 44,
        ),
        const SizedBox(height: 12),
        const Text(
          'Correo enviado',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NerilumColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Revisa ${_emailCtrl.text.trim()} y sigue el enlace para definir '
          'tu nueva contraseña.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: NerilumColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});
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
