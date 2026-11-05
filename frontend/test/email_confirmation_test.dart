import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/account.dart';
import 'package:frontend/domain/repositories/account_repository.dart';
import 'package:frontend/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _EmailAccountRepository extends AccountRepository {
  String? registeredEmail;
  String? resentEmail;
  @override
  bool get isDemo => false;
  @override
  bool get requiresEmailConfirmation => true;
  @override
  Account? get currentAccount => null;
  @override
  Future<Account?> restoreSession() async => null;
  @override
  Future<Account?> login(String email, String password) async => null;
  @override
  Future<bool> register(String email, String password, String name) async {
    registeredEmail = email;
    return true;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    resentEmail = email;
  }

  @override
  Future<void> logout() async {}
}

void main() {
  testWidgets(
    'Registro real espera confirmación y permite reenviar sin sesión mock',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = _EmailAccountRepository();
      final dependencies = AppDependencies(accounts: accounts);
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(NerilumApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrarse'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@ejemplo.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Clave1234');
      await tester.enterText(find.byType(TextFormField).at(3), 'Clave1234');
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Crear cuenta'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Confirma tu correo'), findsOneWidget);
      expect(accounts.registeredEmail, 'ana@ejemplo.com');
      expect(accounts.currentAccount, isNull);
      await tester.tap(find.text('Reenviar confirmación'));
      await tester.pumpAndSettle();
      expect(accounts.resentEmail, 'ana@ejemplo.com');
      await tester.tap(find.text('Ir a iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.textContaining('Demo:'), findsNothing);
      expect(find.textContaining('demo@nerilum.app'), findsNothing);
      expect(find.textContaining('Demo1234'), findsNothing);
      expect(find.textContaining('modo demostración'), findsNothing);
    },
  );
}
