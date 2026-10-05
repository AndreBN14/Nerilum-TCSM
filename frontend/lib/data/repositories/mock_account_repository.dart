import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/mock_account_data_source.dart';
import '../datasources/mock_session_data_source.dart';

class MockAccountRepository extends AccountRepository {
  MockAccountRepository(this.source, this.session);
  final MockAccountDataSource source;
  final MockSessionDataSource session;

  @override
  Account? get currentAccount => source.currentAccount;

  @override
  Future<Account?> restoreSession() async {
    final account = await session.load();
    if (account != null) source.restoreSession(account);
    return account;
  }

  @override
  Future<Account?> login(String email, String password) async {
    final account = source.login(email, password);
    if (account == null) return null;
    try {
      await session.save(account);
    } catch (_) {
      source.logout();
      rethrow;
    }
    return account;
  }

  @override
  Future<bool> register(String email, String password, String name) async =>
      source.register(email, password, name);

  @override
  Future<void> logout() async {
    await session.clear();
    source.logout();
  }
}
