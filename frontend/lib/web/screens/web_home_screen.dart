import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';

class WebHomeScreen extends StatelessWidget {
  const WebHomeScreen({super.key, required this.user});

  final User user;

  String get _displayName {
    final meta = user.userMetadata;
    if (meta != null) {
      final name = meta['display_name'] as String?;
      if (name != null && name.isNotEmpty) return name;
      final fullName = meta['full_name'] as String?;
      if (fullName != null && fullName.isNotEmpty) return fullName;
    }
    // Fallback: parte del correo antes del @
    return user.email?.split('@').first ?? 'Usuario';
  }

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    // El _AuthGate reacciona al stream y vuelve al login automáticamente.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NerilumColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Ícono de sesión activa ─────────────────────────
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: NerilumColors.mint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: NerilumColors.mint.withValues(alpha: 0.35),
                        width: 1.5),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: NerilumColors.mint,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Mensaje principal ──────────────────────────────
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      color: NerilumColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(text: 'Usted '),
                      TextSpan(
                        text: _displayName,
                        style: const TextStyle(
                          color: NerilumColors.mint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' está adentro'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Correo ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: NerilumColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NerilumColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.email_outlined,
                          color: NerilumColors.textSecondary, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Con correo  ',
                        style: const TextStyle(
                          color: NerilumColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        user.email ?? '—',
                        style: const TextStyle(
                          color: NerilumColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Token info (debug visual) ─────────────────────
                _TokenBadge(user: user),

                const SizedBox(height: 40),

                // ── Botón cerrar sesión ───────────────────────────
                OutlinedButton.icon(
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra el UID y la expiración del token — útil para confirmar que el JWT
/// de Supabase llegó bien. Se puede quitar cuando no sea necesario.
class _TokenBadge extends StatelessWidget {
  const _TokenBadge({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final expiresAt = session?.expiresAt;
    final expText = expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .toLocal()
            .toString()
            .substring(0, 16)
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NerilumColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NerilumColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  color: NerilumColors.mint, size: 15),
              const SizedBox(width: 6),
              const Text(
                'Sesión activa  ·  JWT Supabase',
                style: TextStyle(
                  color: NerilumColors.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'UID', value: user.id),
          const SizedBox(height: 4),
          _InfoRow(label: 'Expira', value: expText),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: NerilumColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: NerilumColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
