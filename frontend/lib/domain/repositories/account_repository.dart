import '../models/account.dart';

abstract class AccountRepository {
  bool get isDemo => true;
  bool get requiresEmailConfirmation => false;
  Stream<Account?> get sessionChanges => const Stream.empty();
  Future<void> resendConfirmation(String email) async {
    throw UnsupportedError('Confirmación no disponible en modo mock.');
  }

  Account? get currentAccount;
  Future<Account?> restoreSession();
  Future<Account?> login(String email, String password);
  Future<bool> register(String email, String password, String name);
  Future<void> logout();
}
