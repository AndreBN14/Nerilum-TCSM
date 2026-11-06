import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/nerilum_theme.dart';

/// Estado de carga de una vista del portal web.
///
/// Toda vista del portal debe representar los cuatro estados obligatorios:
/// cargando, vacío, error de red y sesión expirada. Este widget centraliza
/// los esqueletos visuales para reutilizarlos desde cada pantalla.
enum WebViewStatus { loading, empty, error, sessionExpired, content }

/// ¿El mensaje de error del backend indica sesión expirada o no válida?
///
/// El backend responde 401 con "La sesión no es válida o expiró. Vuelve a
/// iniciar sesión." Cuando una vista recibe ese error debe mostrar el estado
/// de sesión expirada, no un error de red genérico.
bool isSessionExpiredError(String message) {
  final m = message.toLowerCase();
  return m.contains('sesión') &&
      (m.contains('expiró') || m.contains('no es válida'));
}

/// Contenedor que decide qué esqueleto mostrar según [status].
///
/// Cuando [status] es [WebViewStatus.content] se renderiza [content].
/// En [WebViewStatus.loading] usa [loadingBuilder] si se indica (esqueletos
/// con la forma del contenido, recomendado en modo Operate) o un indicador
/// centrado como respaldo. Los demás estados muestran un esqueleto con la
/// acción de reintento indicada.
class WebViewStateBox extends StatelessWidget {
  const WebViewStateBox({
    super.key,
    required this.status,
    required this.content,
    this.loadingBuilder,
    this.onRetry,
    this.emptyTitle = 'Aún no tienes análisis',
    this.emptyHint,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.errorMessage = 'No pudimos cargar la información. Revisa tu conexión.',
  });

  final WebViewStatus status;
  final Widget content;
  final WidgetBuilder? loadingBuilder;
  final VoidCallback? onRetry;
  final String emptyTitle;
  final String? emptyHint;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case WebViewStatus.loading:
        return loadingBuilder?.call(context) ?? const WebViewLoading();
      case WebViewStatus.empty:
        return WebViewEmpty(
          title: emptyTitle,
          hint: emptyHint,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
        );
      case WebViewStatus.error:
        return WebViewError(message: errorMessage, onRetry: onRetry);
      case WebViewStatus.sessionExpired:
        return const WebViewSessionExpired();
      case WebViewStatus.content:
        return content;
    }
  }
}

/// Esqueleto de carga centrado con indicador y etiqueta textual.
class WebViewLoading extends StatelessWidget {
  const WebViewLoading({super.key, this.label = 'Cargando…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(color: NerilumColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío. Por defecto anuncia "Aún no tienes análisis".
class WebViewEmpty extends StatelessWidget {
  const WebViewEmpty({
    super.key,
    this.title = 'Aún no tienes análisis',
    this.hint,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.history,
  });

  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.mintSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error de red con acción de reintentar.
class WebViewError extends StatelessWidget {
  const WebViewError({
    super.key,
    this.message = 'No pudimos cargar la información. Revisa tu conexión.',
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sesión expirada. El usuario debe volver a iniciar sesión.
class WebViewSessionExpired extends StatelessWidget {
  const WebViewSessionExpired({super.key, this.onRelogin});

  final VoidCallback? onRelogin;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined, size: 40, color: colors.error),
            const SizedBox(height: 12),
            const Text(
              'Tu sesión expiró',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Vuelve a iniciar sesión para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            if (onRelogin != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRelogin,
                child: const Text('Iniciar sesión'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────
// Esqueletos de carga (skeletons)
//
// En modo Operate, el estado de carga muestra placeholders con la forma del
// contenido que va a aparecer, no un indicador centrado en medio del contenido.
// Estos bloques pulsantes respetan "reducir animaciones" del sistema.
// ─────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.width, required this.height, this.radius = 8});
  final double width;
  final double height;
  final double radius;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final base = colors.surfaceRaised;
    final highlight = colors.surface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = reduceMotion ? 0.5 : _controller.value;
        final color = Color.lerp(base, highlight, (math.sin(t * math.pi * 2) + 1) / 2);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color ?? base,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Línea de esqueleto (texto placeholder).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      _Shimmer(width: width, height: height, radius: radius);
}

/// Bloque de esqueleto (tarjeta/contenedor placeholder).
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    this.height = 80,
    this.radius = 20,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      _Shimmer(width: width, height: height, radius: radius);
}

/// Círculo de esqueleto (avatar placeholder).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) =>
      _Shimmer(width: size, height: size, radius: size / 2);
}

/// Lista de N filas de esqueleto, con la forma de un registro de historial.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 4});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const SkeletonBlock(height: 64, radius: 18),
    );
  }
}

/// Esqueleto de la vista Inicio: saludo + dos tarjetas resumen + una fila.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SkeletonLine(width: 180, height: 26),
        const SizedBox(height: 6),
        const SkeletonLine(width: 240, height: 14),
        const SizedBox(height: 24),
        Row(
          children: const [
            Expanded(child: SkeletonBlock(height: 96)),
            SizedBox(width: 16),
            Expanded(child: SkeletonBlock(height: 96)),
          ],
        ),
        const SizedBox(height: 24),
        const SkeletonBlock(height: 72, radius: 20),
      ],
    );
  }
}

/// Esqueleto de la vista Historial: filtros + lista de filas.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key, this.rows = 5});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            SkeletonLine(width: 150, height: 36, radius: 20),
            SizedBox(width: 12),
            SkeletonLine(width: 150, height: 36, radius: 20),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(child: SkeletonList(itemCount: rows)),
      ],
    );
  }
}

/// Esqueleto de la vista Detalle de análisis.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SkeletonBlock(height: 76, radius: 20),
        const SizedBox(height: 12),
        const SkeletonBlock(height: 92, radius: 18),
        const SizedBox(height: 12),
        const SkeletonLine(width: 180, height: 18),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++) ...[
          const SkeletonLine(height: 14),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
