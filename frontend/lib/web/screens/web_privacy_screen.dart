import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';

/// Vista Privacidad del portal web.
///
/// Muestra: exportar mis datos y eliminar mi cuenta.
///
/// Estado de los endpoints (sección 5 del diseño):
///   - GET  /api/v1/me/export  — NO implementado aún en el backend.
///   - DELETE /api/v1/me       — NO implementado aún en el backend.
///
/// Las acciones muestran un aviso honesto de "pendiente de implementación"
/// en lugar de simular un éxito. Cuando el backend los implemente, solo hay
/// que sustituir el cuerpo de [_exportData] y [_deleteAccount].
class WebPrivacyScreen extends StatefulWidget {
  const WebPrivacyScreen({super.key, required this.user});

  final User user;

  @override
  State<WebPrivacyScreen> createState() => _WebPrivacyScreenState();
}

class _WebPrivacyScreenState extends State<WebPrivacyScreen> {
  String? _error;
  String? _info;

  // ── Exportar datos ─────────────────────────────────────────────────────────
  //
  // Cuando el backend implemente GET /api/v1/me/export, reemplaza este cuerpo:
  //
  //   final source = ... // HttpAnalysisDataSource u otro cliente HTTP
  //   final bytes = await source.exportMyData(); // método por añadir
  //   // Abrir descarga en el navegador con el paquete `universal_html` o similar
  //
  Future<void> _exportData() async {
    setState(() {
      _error = null;
      _info = null;
    });

    // El endpoint GET /api/v1/me/export todavía no existe en el backend.
    // Mientras no esté implementado, informamos al usuario con honestidad.
    setState(() {
      _info =
          'La exportación de datos aún no está disponible. El endpoint del '
          'backend (GET /api/v1/me/export) está pendiente de implementación.';
    });
  }

  // ── Eliminar cuenta ────────────────────────────────────────────────────────
  //
  // Cuando el backend implemente DELETE /api/v1/me, reemplaza el cuerpo del
  // bloque "pendiente" por la llamada HTTP real, y después cierra sesión:
  //
  //   await client.delete(Uri.parse('$baseUrl/api/v1/me'),
  //       headers: {'Authorization': 'Bearer $token'});
  //   await Supabase.instance.client.auth.signOut();
  //   // El _AuthGate vuelve al login.
  //
  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta acción es permanente y borrará tus análisis y tu perfil. '
          'No se puede deshacer. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // El endpoint DELETE /api/v1/me todavía no existe en el backend.
    setState(() {
      _info = null;
      _error =
          'La eliminación de cuenta aún no está disponible. El endpoint del '
          'backend (DELETE /api/v1/me) está pendiente de implementación.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return WebPageScaffold(
      title: 'Privacidad',
      status: WebViewStatus.content,
      contentBuilder: (_) => ListView(
        children: [
          if (_info != null) ...[
            _Banner(message: _info!, isError: false),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            _Banner(message: _error!, isError: true),
            const SizedBox(height: 16),
          ],

          // ── Quién gestiona tus datos ───────────────────────────────────
          _SectionNote(
            icon: Icons.shield_outlined,
            text:
                'Supabase Auth gestiona tu identidad y sesión. El backend '
                'Nerilum almacena únicamente tus análisis y el nombre de '
                'perfil. Las imágenes nunca se guardan en el servidor.',
            colors: colors,
          ),
          const SizedBox(height: 20),

          // ── Exportar datos ─────────────────────────────────────────────
          _PrivacyAction(
            icon: Icons.download_outlined,
            title: 'Exportar mis datos',
            description:
                'Descarga una copia de tus análisis y datos de perfil. '
                'Pendiente de implementación en el backend.',
            actionLabel: 'Exportar datos',
            actionIcon: Icons.file_download_outlined,
            onAction: _exportData,
            pendingNote: true,
            colors: colors,
          ),
          const SizedBox(height: 16),

          // ── Eliminar cuenta ────────────────────────────────────────────
          _PrivacyAction(
            icon: Icons.delete_forever_outlined,
            title: 'Eliminar mi cuenta',
            description:
                'Borra permanentemente tu cuenta y todos tus análisis. '
                'No se puede deshacer. Pendiente de implementación en el backend.',
            actionLabel: 'Solicitar eliminación',
            actionIcon: Icons.delete_outline,
            onAction: _confirmAndDelete,
            pendingNote: true,
            destructive: true,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

class _SectionNote extends StatelessWidget {
  const _SectionNote({
    required this.icon,
    required this.text,
    required this.colors,
  });

  final IconData icon;
  final String text;
  final NerilumPalette colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _PrivacyAction extends StatelessWidget {
  const _PrivacyAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.colors,
    this.destructive = false,
    this.pendingNote = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final NerilumPalette colors;
  final bool destructive;
  final bool pendingNote;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? colors.error : colors.mint;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (pendingNote) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          'pendiente',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ],
            ),
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
