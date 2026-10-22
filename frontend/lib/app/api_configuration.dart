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
        uri.hasFragment ||
        authMode != 'supabase') {
      throw StateError(
        'API_BASE_URL requiere una URL HTTP/HTTPS y AUTH_MODE=supabase.',
      );
    }
  }

  Uri get baseUri {
    final uri = Uri.parse(baseUrl.trim());
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '${path.isEmpty ? '/api/v1' : path}/');
  }
}
