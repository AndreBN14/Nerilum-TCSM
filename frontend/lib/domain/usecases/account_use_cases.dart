import '../models/account.dart';
import '../repositories/account_repository.dart';

class LoginAccount {
  const LoginAccount(this.repository);
  final AccountRepository repository;
  Future<Account?> call(String email, String password) =>
      repository.login(email.trim(), password);
}

class RegisterAccount {
  const RegisterAccount(this.repository);
  final AccountRepository repository;
  Future<bool> call(String email, String password, String name) =>
      repository.register(email.trim(), password, name.trim());
}

class LogoutAccount {
  const LogoutAccount(this.repository);
  final AccountRepository repository;
  Future<void> call() => repository.logout();
}

class CurrentAccount {
  const CurrentAccount(this.repository);
  final AccountRepository repository;
  Account? call() => repository.currentAccount;
}
