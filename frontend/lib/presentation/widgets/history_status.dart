import 'package:flutter/material.dart';

class HistoryStatus extends StatelessWidget {
  const HistoryStatus({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.showRetryButton = true,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool showRetryButton;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Cargando historial…')),
          ],
        ),
      );
    }
    if (!showRetryButton && error == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (showRetryButton)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(
              error == null ? 'Actualizar historial' : 'Reintentar historial',
            ),
          ),
      ],
    );
  }
}
