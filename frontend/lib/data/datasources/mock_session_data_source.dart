import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/account.dart';

abstract class MockSessionDataSource {
  Future<Account?> load();
  Future<void> save(Account account);
  Future<void> clear();
}

// Solo conserva identificador y nombre de una sesión DEMO; nunca la contraseña.
class LocalMockSessionDataSource implements MockSessionDataSource {
  LocalMockSessionDataSource({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync preferences;
  static const key = 'nerilum_mock_session';

  @override
  Future<Account?> load() async {
    final saved = await preferences.getString(key);
    if (saved == null) return null;
    try {
      final data = jsonDecode(saved);
      if (data is! Map<String, dynamic>) return null;
      final email = data['email'];
      final name = data['name'];
      if (email is! String ||
          name is! String ||
          email.isEmpty ||
          name.isEmpty) {
        return null;
      }
      return Account(email: email, name: name);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(Account account) => preferences.setString(
    key,
    jsonEncode({'email': account.email, 'name': account.name}),
  );

  @override
  Future<void> clear() => preferences.remove(key);
}
