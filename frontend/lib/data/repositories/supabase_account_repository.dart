import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/supabase_account_data_source.dart';

class SupabaseAccountRepository extends AccountRepository {
  SupabaseAccountRepository(this.source);
  final SupabaseAccountDataSource source;

  @override
  bool get isDemo => false;
  @override
  bool get requiresEmailConfirmation => true;
  @override
  Account? get currentAccount => source.mapUser(source.client.auth.currentUser);
  @override
  Stream<Account?> get sessionChanges => source.sessionChanges;
  @override
  Future<Account?> restoreSession() => source.profile();
  @override
  Future<Account?> login(String email, String password) =>
      source.login(email, password);
  @override
  Future<bool> register(String email, String password, String name) =>
      source.register(email, password, name);
  @override
  Future<void> resendConfirmation(String email) => source.resend(email);
  @override
  Future<void> logout() => source.client.auth.signOut();
}
