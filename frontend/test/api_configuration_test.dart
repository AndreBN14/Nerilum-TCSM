import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/api_configuration.dart';

void main() {
  test('URL vacía mantiene el modo sin API', () {
    const config = ApiConfiguration(baseUrl: '');
    expect(config.enabled, isFalse);
    config.validate(authMode: 'mock');
  });

  for (final base in [
    'http://localhost:8000',
    'http://10.0.2.2:8000/api/v1/',
    'https://api.ejemplo.com/api/v1',
  ]) {
    test('Normaliza la dirección: $base', () {
      final config = ApiConfiguration(baseUrl: base);
      config.validate(authMode: 'supabase');
      final endpoint = config.baseUri.resolve('analyses');
      expect(endpoint.path, '/api/v1/analyses');
      expect(endpoint.host, Uri.parse(base).host);
    });
  }

  test('No acepta URLs ambiguas ni conexión remota con autenticación mock', () {
    for (final value in [
      'localhost:8000',
      'file:///tmp/api',
      'https://user:pass@api.ejemplo.com',
      'https://api.ejemplo.com?token=bad',
      'https://api.ejemplo.com/#section',
    ]) {
      expect(
        () => ApiConfiguration(baseUrl: value).validate(authMode: 'supabase'),
        throwsStateError,
      );
    }
    expect(
      () =>
          const ApiConfiguration(baseUrl: 'https://api.ejemplo.com')
              .validate(authMode: 'mock'),
      throwsStateError,
    );
  });
}
