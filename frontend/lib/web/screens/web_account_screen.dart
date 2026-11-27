import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';
import 'web_forgot_password_dialog.dart';

/// Vista Mi cuenta del portal web.
///
/// Datos necesarios:
///   - Nombre: tabla `profiles` (SELECT display_name FROM profiles WHERE id = uid)
///   - Correo: Supabase Auth (user.email, de solo lectura)
///   - Cambiar contraseña: resetPasswordForEmail(email) — Supabase envía el correo
///     con enlace de vuelta al portal.
///
/// El nombre es de solo lectura y el cierre de sesión vive en la barra
/// lateral del portal, no en esta vista.
class WebAccountScreen extends StatefulWidget {
  const WebAccountScreen({super.key, required this.user});

  final User user;

  @override
  State<WebAccountScreen> createState() => _WebAccountScreenState();
}

class _WebAccountScreenState extends State<WebAccountScreen> {
  bool _changingPass = false;
  WebViewStatus _status = WebViewStatus.loading;
  String? _name;
  String? _error;
  String? _info;

  // El correo nunca cambia en esta sesión; se lee del objeto User.
  String get _email => widget.user.email ?? '—';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ── Carga perfil desde `profiles` ─────────────────────────────────────────

  Future<void> _loadProfile() async {
    setState(() {
      _status = WebViewStatus.loading;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      // SELECT display_name FROM profiles WHERE id = uid
      final row = await client
          .from('profiles')
          .select('display_name')
          .eq('id', widget.user.id)
          .maybeSingle();
      if (!mounted) return;
      // Si no hay fila en profiles, caer al metadata del token.
      final fromProfiles = row?['display_name'] as String?;
      final fromMeta =
          widget.user.userMetadata?['display_name'] as String? ??
          _email.split('@').first;
      final resolved =
          (fromProfiles != null && fromProfiles.isNotEmpty)
              ? fromProfiles
              : fromMeta;
      setState(() {
        _name = resolved;
        _status = WebViewStatus.content;
      });
    } catch (e) {
      if (!mounted) return;
      // Si profiles no responde, mostrar lo que ya tiene el token.
      final fallback =
          widget.user.userMetadata?['display_name'] as String? ??
          _email.split('@').first;
      setState(() {
        _name = fallback;
        // No bloquear la vista: mostrar contenido con aviso de error.
        _error = 'No se pudo cargar el perfil desde la base de datos.';
        _status = WebViewStatus.content;
      });
    }
  }

  // ── Cambiar contraseña vía Supabase ───────────────────────────────────────

  Future<void> _changePassword() async {
    if (_changingPass) return;
    setState(() {
      _changingPass = true;
      _error = null;
      _info = null;
    });
    try {
      // Supabase envía un correo con enlace para restablecer la contraseña.
      // El enlace vuelve al portal (Redirect URLs del dashboard) y el
      // _AuthGate abre la pantalla de nueva contraseña.
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email,
        redirectTo: Uri.base.removeFragment().toString(),
      );
      if (!mounted) return;
      setState(() =>
          _info = 'Te enviamos un correo para cambiar tu contraseña.');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo enviar el correo. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _changingPass = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return WebPageScaffold(
      title: 'Mi cuenta',
      status: _status,
      loadingBuilder: (_) => ListView(
        children: const [
          SkeletonBlock(height: 80, radius: 20),
          SizedBox(height: 20),
          SkeletonLine(width: 120, height: 18),
          SizedBox(height: 12),
          SkeletonLine(height: 14),
          SizedBox(height: 10),
          SkeletonLine(height: 14),
        ],
      ),
      onRetry: _loadProfile,
      emptyTitle: 'Sin sesión activa',
      emptyHint: 'No hay datos de cuenta disponibles.',
      errorMessage: _error ?? 'No se pudo cargar tu perfil.',
      actions: [
        IconButton(
          tooltip: 'Actualizar perfil',
          onPressed: _loadProfile,
          icon: const Icon(Icons.refresh),
        ),
      ],
      contentBuilder: (_) => ListView(
        children: [
          // Mensajes de respuesta
          if (_info != null) ...[
            _Banner(message: _info!, isError: false),
            const SizedBox(height: 16),
          ],
          if (_error != null && _status == WebViewStatus.content) ...[
            _Banner(message: _error!, isError: true),
            const SizedBox(height: 16),
          ],

          // Tarjeta de identidad
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colors.mint.withValues(alpha: 0.16),
                  child: Text(
                    (_name ?? 'U').substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: colors.mint,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name ?? '—',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _email,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 8),

          // Cambiar contraseña
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline, color: colors.textPrimary),
            title: const Text('Cambiar contraseña'),
            subtitle: Text(
              'Enviaremos un correo a $_email.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            trailing: _changingPass
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(Icons.chevron_right, color: colors.textSecondary),
            onTap: _changingPass ? null : _changePassword,
          ),
        ],
      ),
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
