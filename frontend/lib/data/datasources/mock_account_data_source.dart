import '../../domain/models/account.dart';

// El estado mock pertenece a esta instancia; no se comparte entre instalaciones.
class MockAccountDataSource {
  final Map<String, String> _passwords = {'demo@nerilum.app': 'Demo1234'};
  final Map<String, String> _names = {'demo@nerilum.app': 'Cuenta demo'};
  String? _activeEmail;

  Account? get currentAccount => _activeEmail == null
      ? null
      : Account(
          email: _activeEmail!,
          name: _names[_activeEmail!] ?? 'Cuenta demo',
        );

  Account? login(String email, String password) {
    final normalized = email.toLowerCase();
    if (_passwords[normalized] != password) return null;
    _activeEmail = normalized;
    return currentAccount;
  }

  void restoreSession(Account account) {
    final email = account.email.toLowerCase();
    _activeEmail = email;
    _names[email] = account.name;
  }

  bool register(String email, String password, String name) {
    final normalized = email.toLowerCase();
    if (_passwords.containsKey(normalized)) return false;
    _passwords[normalized] = password;
    _names[normalized] = name;
    return true;
  }

  void logout() => _activeEmail = null;
}
