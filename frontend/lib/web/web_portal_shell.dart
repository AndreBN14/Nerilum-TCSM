import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/nerilum_theme.dart';
import '../data/datasources/http_analysis_data_source.dart';
import 'screens/web_home_screen.dart';
import 'screens/web_history_screen.dart';
import 'screens/web_account_screen.dart';
import 'screens/web_privacy_screen.dart';
import 'screens/web_analysis_detail_screen.dart';
import 'screens/web_report_screen.dart';

/// Shell del portal web autenticado.
///
/// Muestra una barra de navegación lateral (web) y conmuta entre las vistas
/// principales: Inicio, Historial, Mi cuenta y Privacidad. El detalle de
/// análisis y el reporte se abren como rutas empujadas desde las vistas.
class WebPortalShell extends StatefulWidget {
  const WebPortalShell({super.key, required this.user, this.analysisSource});

  final User user;
  final HttpAnalysisDataSource? analysisSource;

  @override
  State<WebPortalShell> createState() => _WebPortalShellState();
}

class _WebPortalShellState extends State<WebPortalShell> {
  int _index = 0;

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _Destination(
      label: 'Historial',
      icon: Icons.history,
      selectedIcon: Icons.history_rounded,
    ),
    _Destination(
      label: 'Mi cuenta',
      icon: Icons.person_outline,
      selectedIcon: Icons.person_rounded,
    ),
    _Destination(
      label: 'Privacidad',
      icon: Icons.shield_outlined,
      selectedIcon: Icons.shield_rounded,
    ),
  ];

  void _openAnalysis(String analysisId) {
    // Detalle de análisis: GET /api/v1/analyses/{id}
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebAnalysisDetailScreen(
          analysisId: analysisId,
          user: widget.user,
          analysisSource: widget.analysisSource,
          onOpenReport: () => _openReport(analysisId),
        ),
      ),
    );
  }

  void _openReport(String analysisId) {
    // Reporte PDF: se genera en Flutter con el paquete `pdf`, sin backend.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebReportScreen(
          analysisId: analysisId,
          analysisSource: widget.analysisSource,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    // El _AuthGate de main_web.dart reacciona al stream y vuelve al login.
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          // ── Barra de navegación lateral ────────────────────────────────
          Container(
            width: 232,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/nerilum-mark-512.png',
                          width: 28,
                          height: 28,
                          color: colors.mint,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'NERILUM',
                          style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Portal web',
                      style: TextStyle(
                        color: NerilumColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (var i = 0; i < _destinations.length; i++)
                          _NavTile(
                            destination: _destinations[i],
                            selected: _index == i,
                            onTap: () => setState(() => _index = i),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.user.email ?? '—',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Contenido principal ─────────────────────────────────────────
          Expanded(
            child: SafeArea(
              child: IndexedStack(
                index: _index,
                children: [
                  WebHomeScreen(
                    user: widget.user,
                    analysisSource: widget.analysisSource,
                    onOpenHistory: () => setState(() => _index = 1),
                    onOpenAnalysis: _openAnalysis,
                  ),
                  WebHistoryScreen(
                    user: widget.user,
                    analysisSource: widget.analysisSource,
                    onOpenAnalysis: _openAnalysis,
                  ),
                  WebAccountScreen(user: widget.user),
                  WebPrivacyScreen(
                    user: widget.user,
                    analysisSource: widget.analysisSource,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? colors.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: selected ? colors.mint : colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: selected ? colors.textPrimary : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

