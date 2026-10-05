class AuthConfiguration {
  const AuthConfiguration({
    this.mode = const String.fromEnvironment('AUTH_MODE', defaultValue: 'mock'),
    this.url = const String.fromEnvironment('SUPABASE_URL'),
    this.key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    this.redirect = const String.fromEnvironment(
      'AUTH_REDIRECT_URL',
      defaultValue: 'app.nerilum://auth-callback',
    ),
  });

  final String mode;
  final String url;
  final String key;
  final String redirect;
  bool get isSupabase => mode == 'supabase';

  void validate() {
    if (mode != 'mock' && mode != 'supabase') {
      throw StateError('AUTH_MODE debe ser mock o supabase.');
    }
    if (!isSupabase) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        key.isEmpty) {
      throw StateError(
        'Configura SUPABASE_URL HTTPS y SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    final callback = Uri.tryParse(redirect);
    if (callback == null || !callback.hasScheme) {
      throw StateError('Configura AUTH_REDIRECT_URL.');
    }
  }
}
