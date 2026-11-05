import 'package:flutter/foundation.dart';

/// Identidad local para la cola. `verified` nunca sustituye la validación JWT
/// que hace el backend cuando se restablece la conexión.
class SessionController extends ChangeNotifier {
  String? ownerId;
  bool verified = false;

  void restore(String? id) {
    ownerId = id;
    verified = false;
    notifyListeners();
  }

  void markVerified(String id) {
    ownerId = id;
    verified = true;
    notifyListeners();
  }

  void markUnverified() {
    if (ownerId == null || !verified) return;
    verified = false;
    notifyListeners();
  }

  void signOut() {
    ownerId = null;
    verified = false;
    notifyListeners();
  }
}
