import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e_actions.dart';
import 'helpers/e2e_app.dart';
import 'helpers/e2e_config.dart';
import 'helpers/e2e_screenshots.dart';
import 'helpers/e2e_wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restauración de sesión real tras reiniciar la app', (
    tester,
  ) async {
    final config = E2EConfig.fromEnvironment();
    config.validate();
    await withE2EScreenshots(tester, 'session', (shots) async {
      final session = await pumpRealApp(tester, config);
      await shots.capture('session-01-app');
      await login(tester, config);
      await shots.capture('session-02-login');
      expect(find.text('Perfil'), findsOneWidget);
      await session.dispose(tester);

      final restored = await pumpRealApp(tester, config);
      addTearDown(() => restored.dispose(tester));
      await pumpUntilAnyText(tester, const [
        'Perfil',
        'Iniciar sesión',
      ], timeout: const Duration(seconds: 60));
      await shots.capture('session-03-restored');
      expect(find.text('Perfil'), findsOneWidget);
      expect(restored.accessToken, isNotNull);
    });
  });
}
