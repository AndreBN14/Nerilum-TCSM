import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../core/utils/category_label.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';
import '../web_page_scaffold.dart';
import '../widgets/web_dialogs.dart';
import '../widgets/web_download.dart';

/// Vista Privacidad del portal web.
///
/// Muestra: exportar mis datos y eliminar mi cuenta.
///
/// Estado de los endpoints (sección 5 del diseño):
///   - Exportar datos: NO requiere backend; usa GET /api/v1/analyses
///     (existente) + la identidad de Supabase, y descarga un JSON en el
///     navegador.
///   - DELETE /api/v1/me — NO implementado aún en el backend.
///
/// La eliminación de cuenta sigue mostrando un aviso honesto de "pendiente
/// de implementación". Cuando el backend la implemente, solo hay que
/// sustituir el cuerpo de [_deleteAccount].
class WebPrivacyScreen extends StatefulWidget {
  const WebPrivacyScreen({super.key, required this.user, this.analysisSource});

  final User user;

  // null cuando API_BASE_URL no está configurada.
  final HttpAnalysisDataSource? analysisSource;

  @override
  State<WebPrivacyScreen> createState() => _WebPrivacyScreenState();
}

class _WebPrivacyScreenState extends State<WebPrivacyScreen> {
  String? _error;
  String? _info;
  bool _exporting = false;

  // ── Exportar datos ─────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _error = null;
      _info = null;
    });
    try {
      final source = widget.analysisSource;
      if (source == null) {
        throw const AnalysisFailure(
          'El backend de análisis no está configurado. '
          'Define API_BASE_URL al ejecutar la app.',
        );
      }

      // Nombre de perfil: profiles con respaldo en el metadata del token.
      String? nombre;
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('display_name')
            .eq('id', widget.user.id)
            .maybeSingle();
        nombre = row?['display_name'] as String?;
      } catch (_) {
        // Sin acceso a profiles seguimos exportando lo demás.
      }
      nombre ??= widget.user.userMetadata?['display_name'] as String?;

      // Historial completo: GET /api/v1/analyses (pagina todo el backend).
      final history = await source.history();

      final u = widget.user;
      final data = <String, dynamic>{
        'exportado': DateTime.now().toIso8601String(),
        'cuenta': {
          'id': u.id,
          'email': u.email,
          'nombre': nombre,
          'creado_el': u.createdAt,
        },
        'resumen': {'total_analisis': history.length},
        'notas':
            'Las imágenes de los análisis se almacenan en Supabase Storage '
            '(bucket privado) y se descargan individualmente desde el '
            'detalle de cada análisis. Este archivo no incluye su contenido '
            'binario.',
        'analises': [
          for (final r in history)
            <String, dynamic>{
              'id': r.id,
              'fecha': r.createdAt.toIso8601String(),
              'nombre': r.displayName,
              'categoria': r.category,
              'categoria_es': categoryLabel(r.category),
              'probabilidad': r.probability,
              'puntuaciones': r.scores,
              'modelo': r.modelName,
              'version_modelo': r.modelVersion,
              'dataset_modelo': r.modelDataset,
              'tiene_imagen': r.hasImage,
              'tiene_mapa_atencion': r.hasGradcam,
              'es_demo': r.isDemo,
            },
        ],
      };

      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      downloadFile(
        filename: 'mis-datos-nerilum-$date.json',
        bytes: utf8.encode(json),
        mime: 'application/json',
      );
      if (!mounted) return;
      setState(() {
        _info =
            'Exportación lista: ${history.length} análisis descargados '
            'como mis-datos-nerilum-$date.json.';
      });
    } on AnalysisFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'No se pudo generar la exportación. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    final ok = await showBlurDialog<bool>(
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
                'Nerilum almacena tus análisis en Postgres y sus imágenes '
                'en un bucket privado de Supabase Storage, accesibles solo '
                'con tu sesión.',
            colors: colors,
          ),
          const SizedBox(height: 20),

          // ── Exportar datos ─────────────────────────────────────────────
          _PrivacyAction(
            icon: Icons.download_outlined,
            title: 'Exportar mis datos',
            description:
                'Descarga una copia de tus análisis y datos de perfil en '
                'formato JSON, legible por cualquier herramienta.',
            actionLabel: 'Descargar JSON',
            actionIcon: Icons.file_download_outlined,
            onAction: _exporting ? () {} : _exportData,
            busy: _exporting,
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
    this.busy = false,
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

  /// true mientras la acción está en curso: el botón queda deshabilitado
  /// y muestra un spinner.
  final bool busy;

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
                  onPressed: busy ? null : onAction,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(actionIcon, size: 18),
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
