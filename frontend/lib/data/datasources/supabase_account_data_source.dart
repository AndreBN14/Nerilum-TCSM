import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/account.dart';

class SupabaseAccountDataSource {
  const SupabaseAccountDataSource(this.client, this.redirect);
  final SupabaseClient client;
  final String redirect;

  Account? mapUser(User? user) => user == null
      ? null
      : Account(
          id: user.id,
          name:
              user.userMetadata?['display_name'] as String? ??
              (user.email?.split('@').first ?? 'Usuario'),
          email: user.email ?? '',
        );

  Future<Account?> profile() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await client
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();
      // Un cambio de cuenta durante la petición no puede devolver el perfil ajeno.
      if (client.auth.currentUser?.id != user.id) {
        return mapUser(client.auth.currentUser);
      }
      return Account(
        id: user.id,
        name: row?['display_name'] as String? ?? mapUser(user)!.name,
        email: user.email ?? '',
      );
    } catch (_) {
      // La sesión local permite abrir la app cuando profiles no responde.
      return mapUser(client.auth.currentUser);
    }
  }

  Future<Account?> login(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
    return profile();
  }

  Future<bool> register(String email, String password, String name) async {
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': name},
      emailRedirectTo: redirect,
    );
    // Confirm Email debe estar activado en Supabase. No aceptar sesión inmediata.
    if (client.auth.currentSession != null) await client.auth.signOut();
    return true;
  }

  Future<void> resend(String email) => client.auth.resend(
    type: OtpType.signup,
    email: email,
    emailRedirectTo: redirect,
  );

  Stream<Account?> get sessionChanges => client.auth.onAuthStateChange.map(
    (event) => event.event == AuthChangeEvent.signedOut
        ? null
        : mapUser(event.session?.user ?? client.auth.currentUser),
  );
}
