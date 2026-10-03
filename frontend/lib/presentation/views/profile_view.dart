import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../domain/models/account.dart';
import '../../domain/models/appearance.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/main_components.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.account,
    required this.onHistory,
    required this.onLogout,
  });

  final Account? account;
  final VoidCallback onHistory;
  final VoidCallback onLogout;

  void _openPage(BuildContext context, String title, Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InfoPage(title: title, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MainPageWidth(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      children: [
        const Text(
          'Mi perfil',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 30),
        _ProfileTile(
          title: account?.name ?? 'Cuenta demo',
          subtitle: account?.email ?? 'Cuenta de demostración',
          icon: Icons.person,
          tall: true,
          onTap: () => _openPage(context, 'Mi cuenta', _AccountInfo(account)),
        ),
        const SizedBox(height: 18),
        _ProfileTile(
          title: 'Mi cuenta',
          icon: Icons.person_outline,
          onTap: () => _openPage(context, 'Mi cuenta', _AccountInfo(account)),
        ),
        _ProfileTile(
          title: 'Preferencias',
          icon: Icons.settings_outlined,
          onTap: () => _openPage(context, 'Preferencias', const _Preferences()),
        ),
        _ProfileTile(
          title: 'Historial completo',
          icon: Icons.history,
          onTap: onHistory,
        ),
        _ProfileTile(
          title: 'Privacidad y datos',
          icon: Icons.shield_outlined,
          onTap: () => _openPage(
            context,
            'Privacidad y datos',
            const Text(
              'Esta demostración permite seleccionar una imagen local para verla en pantalla. '
              'No se envía a un servicio de análisis. El historial de la cuenta demo '
              'contiene únicamente ejemplos precargados, no resultados ni imágenes reales. '
              'El selector del dispositivo puede crear archivos temporales; la selección en memoria '
              'deja de estar disponible al cerrar la aplicación.',
            ),
          ),
        ),
        _ProfileTile(
          title: 'Acerca de Nerilum',
          icon: Icons.info_outline,
          onTap: () => _openPage(
            context,
            'Acerca de Nerilum',
            const Text(
              'Nerilum · Prototipo académico\nVersión 1.0.0\n\n'
              'Explora el diseño de una herramienta de clasificación de imágenes cerebrales. '
              'El modelo de IA todavía no está conectado; no produce resultados ni diagnósticos médicos.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ProfileTile(
          title: 'Cerrar sesión',
          icon: Icons.logout,
          destructive: true,
          onTap: onLogout,
        ),
      ],
    ),
  );
}

class _AccountInfo extends StatelessWidget {
  const _AccountInfo(this.account);

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nombre', style: TextStyle(color: colors.textSecondary)),
        Text(
          account?.name ?? 'Cuenta demo',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 22),
        Text(
          'Correo electrónico',
          style: TextStyle(color: colors.textSecondary),
        ),
        Text(
          account?.email ?? 'Sin sesión',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 22),
        const Text(
          'Esta demostración recuerda nombre y correo en el dispositivo hasta '
          'cerrar sesión. No se guarda la contraseña.',
        ),
      ],
    );
  }
}

class _Preferences extends StatelessWidget {
  const _Preferences();

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context).appearanceViewModel;
    return AnimatedBuilder(
      animation: model,
      builder: (context, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apariencia',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Elige cómo se muestra Nerilum. El modo oscuro es el predeterminado.',
          ),
          const SizedBox(height: 20),
          SegmentedButton<AppAppearance>(
            segments: const [
              ButtonSegment(
                value: AppAppearance.light,
                label: Text('Claro'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: AppAppearance.dark,
                label: Text('Oscuro'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {model.appearance},
            onSelectionChanged: (selection) async {
              if (!await model.setAppearance(selection.single) &&
                  context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No se pudo guardar la apariencia. Inténtalo de nuevo.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'La aplicación respeta la preferencia de reducir animaciones '
            'configurada en tu dispositivo. Puedes cambiar el tamaño del texto '
            'desde los ajustes de accesibilidad del sistema.',
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.tall = false,
    this.destructive = false,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool tall;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: BoxConstraints(minHeight: tall ? 108 : 60),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: tall ? 44 : 26,
                  color: destructive ? colors.error : colors.textPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: tall ? 20 : 16,
                          color: destructive
                              ? colors.error
                              : colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: destructive ? colors.error : colors.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
