import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e_actions.dart';
import 'helpers/e2e_api.dart';
import 'helpers/e2e_app.dart';
import 'helpers/e2e_config.dart';
import 'helpers/e2e_screenshots.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login real y contrato API del sistema', (tester) async {
    final config = E2EConfig.fromEnvironment();
    config.validate();
    await withE2EScreenshots(tester, 'smoke', (shots) async {
      final session = await pumpRealApp(tester, config);
      addTearDown(() => session.dispose(tester));

      await shots.capture('smoke-01-app');
      await login(tester, config);
      await shots.capture('smoke-02-login');
      expect(session.accessToken, isNotNull);

      final api = E2EApiClient(config, () => session.accessToken);
      final me = await api.getJson('auth/me');
      expect(me['account']['id'], isNotEmpty);

      final health = await api.getJson('health');
      expect(health['model_ready'], isA<bool>());

      final openapi = await api.getRootJson('openapi.json');
      final paths = openapi['paths'] as Map<String, dynamic>;
      expect(paths.containsKey('/api/v1/analyses/preview'), isTrue);
      expect(paths.containsKey('/api/v1/analyses/save-with-image'), isTrue);
      expect(paths.containsKey('/api/v1/analyses/{analysis_id}/image'), isTrue);

      await openHistory(tester);
      await shots.capture('smoke-03-history');
      await logout(tester);
      await shots.capture('smoke-04-logout');
    });
  });
}
