import 'dart:ui';

import 'package:flutter/material.dart';

/// Diálogo del portal con fondo desenfocado.
///
/// Envuelve [showGeneralDialog] para añadir un `BackdropFilter` a pantalla
/// completa detrás de la tarjeta: la aplicación queda desenfocada y
/// atenuada mientras el modal está abierto, centrando la atención en él.
/// Tocar fuera de la tarjeta cierra el diálogo.
///
/// Los modales del portal (recuperación de contraseña, rango de fechas,
/// confirmaciones) lo usan para comportarse de forma idéntica.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Cerrar',
    // La capa oscura la aporta el propio BackdropFilter; el barrier real
    // queda transparente para no atenuar dos veces.
    barrierColor: Colors.transparent,
    pageBuilder: (context, animation, secondaryAnimation) {
      return GestureDetector(
        onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: builder(context),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
