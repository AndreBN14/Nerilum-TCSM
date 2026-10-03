import '../models/account.dart';

abstract class AccountRepository {
  Account? get currentAccount;
  Future<Account?> restoreSession();
  Future<Account?> login(String email, String password);
  Future<bool> register(String email, String password, String name);
  Future<void> logout();
}
