import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e_actions.dart';
import 'helpers/e2e_api.dart';
import 'helpers/e2e_app.dart';
import 'helpers/e2e_config.dart';
import 'helpers/e2e_image_repository.dart';
import 'helpers/e2e_screenshots.dart';
import 'helpers/e2e_wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cola offline cifrada y sincronización real', (tester) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final config = E2EConfig.fromEnvironment();
    config.validate();
    await withE2EScreenshots(tester, 'offline', (shots) async {
      final connectivity = StreamController<bool>.broadcast();
      final session = await pumpRealApp(
        tester,
        config,
        images: E2EImageRepository(config),
        networkAvailability: connectivity.stream,
      );
      connectivity.add(false);
      addTearDown(connectivity.close);
      addTearDown(() => session.dispose(tester));

      await shots.capture('offline-01-app');
      await login(tester, config);
      await shots.capture('offline-02-login');
      await openAnalysisTab(tester);
      await selectE2EImage(tester);
      await tester.tap(find.text('Analizar imagen'));
      await pumpUntilTextContaining(
        tester,
        'guarda la imagen como pendiente',
        timeout: const Duration(seconds: 120),
      );
      await shots.capture('offline-03-network-error');
      await tester.tap(find.text('Guardar imagen pendiente en el dispositivo'));
      await pumpUntilText(tester, 'Guardar pendiente');
      await tester.tap(find.text('Guardar pendiente'));
      await pumpUntilText(
        tester,
        'Imagen pendiente guardada en este dispositivo.',
        timeout: const Duration(seconds: 60),
      );
      await shots.capture('offline-04-pending-saved');
      await tester.tap(find.text('Inicio'));
      await pumpUntilTextContaining(
        tester,
        'Pendiente local',
        timeout: const Duration(seconds: 60),
      );
      await shots.capture('offline-05-pending-home');

      connectivity.add(true);
      await pumpUntilText(
        tester,
        'Resultado listo',
        timeout: const Duration(seconds: 180),
      );
      await shots.capture('offline-06-result-ready');
      await tester.tap(find.text('Ver resultado'));
      await pumpUntilText(
        tester,
        'Guardar en historial',
        timeout: const Duration(seconds: 120),
      );
      await shots.capture('offline-07-preview');
      await savePreview(tester, config);
      await shots.capture('offline-08-saved');

      final api = E2EApiClient(config, () => session.accessToken);
      final list = await api.getJson(
        'analyses',
        query: {'limit': '100', 'offset': '0'},
      );
      final items = (list['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        items.any(
          (item) =>
              item['display_name'] == config.displayName &&
              item['has_image'] == true,
        ),
        isTrue,
      );
    });
  });
}
