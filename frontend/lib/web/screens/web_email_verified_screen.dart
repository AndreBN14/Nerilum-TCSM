import 'package:flutter/material.dart';

import '../../core/theme/nerilum_theme.dart';

/// Pantalla de éxito tras verificar el correo de registro.
///
/// El enlace de confirmación (token_hash + type=signup) llega a esta
/// pantalla: la cuenta ya está verificada y autenticada, y el usuario
/// elige continuar al portal o cerrar la pestaña (la sesión queda
/// persistida en el navegador).
class WebEmailVerifiedScreen extends StatelessWidget {
  const WebEmailVerifiedScreen({
    super.key,
    required this.email,
    required this.onContinue,
  });

  final String email;
  final VoidCallback onContinue;

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo de la marca (con respaldo si el asset no carga).
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
                  const SizedBox(height: 24),
                  const Icon(
                    Icons.verified_outlined,
                    color: NerilumColors.mint,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Correo verificado',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NerilumColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu cuenta $email ya está activa y lista para usar.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: NerilumColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onContinue,
                    child: const Text('Continuar al portal'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes cerrar esta pestaña y volver al portal cuando '
                    'quieras: tu sesión ya quedó iniciada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NerilumColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
