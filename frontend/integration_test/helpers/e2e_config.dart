class E2EConfig {
  const E2EConfig({
    required this.authMode,
    required this.supabaseUrl,
    required this.supabaseKey,
    required this.redirect,
    required this.apiBaseUrl,
    required this.verificationApiBaseUrl,
    required this.email,
    required this.password,
    required this.displayName,
    required this.imageAsset,
    this.secondEmail = '',
    this.secondPassword = '',
  });

  final String authMode;
  final String supabaseUrl;
  final String supabaseKey;
  final String redirect;
  final String apiBaseUrl;
  final String verificationApiBaseUrl;
  final String email;
  final String password;
  final String displayName;
  final String imageAsset;
  final String secondEmail;
  final String secondPassword;

  static E2EConfig fromEnvironment() {
    const api = String.fromEnvironment('API_BASE_URL');
    const verification = String.fromEnvironment(
      'E2E_VERIFICATION_API_BASE_URL',
    );
    return E2EConfig(
      authMode: const String.fromEnvironment(
        'AUTH_MODE',
        defaultValue: 'supabase',
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      redirect: const String.fromEnvironment(
        'AUTH_REDIRECT_URL',
        defaultValue: 'app.nerilum://auth-callback',
      ),
      apiBaseUrl: api,
      verificationApiBaseUrl: verification.isEmpty ? api : verification,
      email: const String.fromEnvironment('E2E_EMAIL'),
      password: const String.fromEnvironment('E2E_PASSWORD'),
      displayName: const String.fromEnvironment(
        'E2E_DISPLAY_NAME',
        defaultValue: 'E2E Nerilum',
      ),
      imageAsset: const String.fromEnvironment(
        'E2E_IMAGE_ASSET',
        defaultValue: 'assets/nerilum-mark-512.png',
      ),
      secondEmail: const String.fromEnvironment('E2E_SECOND_EMAIL'),
      secondPassword: const String.fromEnvironment('E2E_SECOND_PASSWORD'),
    );
  }

  void validate() {
    final problems = <String>[];
    if (authMode != 'supabase') {
      problems.add('AUTH_MODE debe ser supabase');
    }
    final supabaseUri = Uri.tryParse(supabaseUrl);
    if (supabaseUri == null ||
        supabaseUri.scheme != 'https' ||
        supabaseUri.host.isEmpty) {
      problems.add('SUPABASE_URL HTTPS válida');
    }
    if (supabaseKey.isEmpty) {
      problems.add('SUPABASE_PUBLISHABLE_KEY');
    }
    final apiUri = Uri.tryParse(apiBaseUrl);
    if (apiUri == null ||
        !['http', 'https'].contains(apiUri.scheme) ||
        apiUri.host.isEmpty) {
      problems.add('API_BASE_URL');
    }
    if (verificationApiBaseUrl.isEmpty) {
      problems.add('E2E_VERIFICATION_API_BASE_URL o API_BASE_URL');
    }
    if (!email.contains('@') || password.isEmpty) {
      problems.add('E2E_EMAIL y E2E_PASSWORD');
    }
    if (problems.isNotEmpty) {
      throw StateError("Configuración E2E incompleta: ${problems.join('; ')}");
    }
  }
}
