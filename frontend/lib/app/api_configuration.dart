class ApiConfiguration {
  const ApiConfiguration({
    this.baseUrl = const String.fromEnvironment('API_BASE_URL'),
  });

  final String baseUrl;
  bool get enabled => baseUrl.trim().isNotEmpty;

  void validate({required String authMode}) {
    if (!enabled) return;
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'API_BASE_URL debe ser una URL HTTP/HTTPS sin credenciales, query ni fragmento.',
      );
    }
    if (authMode != 'supabase') {
      throw StateError('El backend remoto necesita AUTH_MODE=supabase.');
    }
  }

  Uri get baseUri {
    final uri = Uri.parse(baseUrl.trim());
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '${path.isEmpty ? '/api/v1' : path}/');
  }
}
