import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/presentation/viewmodels/session_controller.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('La sesión local conserva UUID estable y no confunde refresh fallido con logout', () async {
    final first = AppDependencies();
    await first.accountRepository.login('demo@nerilum.app', 'Demo1234');
    final id = first.accountRepository.currentAccount!.id;
    expect(id, isNotEmpty);
    first.dispose();

    final reopened = AppDependencies();
    addTearDown(reopened.dispose);
    await reopened.restoreLocalState();
    expect(reopened.sessionController.ownerId, id);
    expect(reopened.sessionController.verified, isFalse);
    expect(reopened.accountRepository.currentAccount!.id, id);
    reopened.sessionController.markVerified(id);
    reopened.sessionController.markUnverified();
    expect(reopened.sessionController.ownerId, id);
    expect(reopened.accountRepository.currentAccount, isNotNull);
    await reopened.mainViewModel.logout();
    expect(reopened.sessionController.ownerId, isNull);
  });

  test(
    'Un cambio de propietario sustituye la identidad sin cambiar de email',
    () {
      final session = SessionController();
      addTearDown(session.dispose);
      session.restore('user-a');
      session.markVerified('user-b');
      expect(session.ownerId, 'user-b');
      expect(session.verified, isTrue);
      session.markUnverified();
      expect(session.ownerId, 'user-b');
      expect(session.verified, isFalse);
    },
  );
}
