import 'package:flutter/foundation.dart';

import '../../domain/usecases/account_use_cases.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required this.loginAccount, required this.registerAccount});

  final LoginAccount loginAccount;
  final RegisterAccount registerAccount;
  bool busy = false;
  String? error;
  bool _disposed = false;

  Future<bool> login(String email, String password) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final account = await loginAccount(email, password);
      if (account == null) {
        error = 'Correo o contraseña incorrectos para esta demostración.';
      }
      return account != null;
    } catch (_) {
      error = 'No se pudo iniciar sesión. Inténtalo de nuevo.';
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
      if (!created) error = 'Ese correo ya tiene una cuenta de demostración.';
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
