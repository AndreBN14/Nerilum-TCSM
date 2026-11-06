import 'package:flutter/material.dart';

import '../core/theme/nerilum_theme.dart';
import 'states/web_view_states.dart';

/// Andamiaje de página del portal web: título, acciones opcionales y el
/// control de los cuatro estados obligatorios (cargando, vacío, error y
/// sesión expirada).
class WebPageScaffold extends StatelessWidget {
  const WebPageScaffold({
    super.key,
    required this.title,
    required this.status,
    required this.contentBuilder,
    this.loadingBuilder,
    this.onRetry,
    this.emptyTitle = 'Aún no tienes análisis',
    this.emptyHint,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.errorMessage = 'No pudimos cargar la información. Revisa tu conexión.',
    this.actions,
  });

  final String title;
  final WebViewStatus status;
  final WidgetBuilder contentBuilder;
  final WidgetBuilder? loadingBuilder;
  final VoidCallback? onRetry;
  final String emptyTitle;
  final String? emptyHint;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String errorMessage;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...?actions,
                ],
              ),
              const SizedBox(height: 4),
              Divider(color: colors.border, height: 24),
              Expanded(
                child: WebViewStateBox(
                  status: status,
                  loadingBuilder: loadingBuilder,
                  onRetry: onRetry,
                  emptyTitle: emptyTitle,
                  emptyHint: emptyHint,
                  emptyActionLabel: emptyActionLabel,
                  onEmptyAction: onEmptyAction,
                  errorMessage: errorMessage,
                  content: contentBuilder(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
