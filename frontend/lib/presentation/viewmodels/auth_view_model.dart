import 'package:flutter/foundation.dart';

import '../../domain/usecases/account_use_cases.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    required this.loginAccount,
    required this.registerAccount,
    required this.resendConfirmation,
    required this.authCapabilities,
  });

  final LoginAccount loginAccount;
  final RegisterAccount registerAccount;
  final ResendConfirmation resendConfirmation;
  final GetAuthCapabilities authCapabilities;

  bool get isDemo => authCapabilities.isDemo;
  bool get requiresEmailConfirmation =>
      authCapabilities.requiresEmailConfirmation;

  bool busy = false;
  String? error;
  bool _disposed = false;

  Future<bool> resend(String email) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await resendConfirmation(email);
      return true;
    } catch (_) {
      error =
          'No se pudo reenviar el correo. Espera unos minutos e inténtalo de nuevo.';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final account = await loginAccount(email, password);
      if (account == null) {
        error = 'Correo o contraseña incorrectos.';
      }
      return account != null;
    } catch (_) {
      error =
          'No se pudo iniciar sesión. Comprueba tu conexión, tus datos y la confirmación del correo.';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String name) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final created = await registerAccount(email, password, name);
      if (!created) {
        error = isDemo
            ? 'Ese correo ya tiene una cuenta de demostración.'
            : 'No se pudo registrar la cuenta. Comprueba tus datos.';
      }
      return created;
    } catch (_) {
      error = 'No se pudo crear la cuenta. Inténtalo de nuevo.';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
