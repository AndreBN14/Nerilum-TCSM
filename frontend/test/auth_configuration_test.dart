import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/auth_configuration.dart';

void main() {
  test('Mock funciona sin claves y Supabase exige valores explícitos', () {
    expect(() => const AuthConfiguration().validate(), returnsNormally);
    expect(
      () => const AuthConfiguration(mode: 'supabase').validate(),
      throwsStateError,
    );
    expect(
      () => const AuthConfiguration(mode: 'otro').validate(),
      throwsStateError,
    );
    expect(
      () => const AuthConfiguration(
        mode: 'supabase',
        url: 'https://test.supabase.co',
        key: 'public-test',
      ).validate(),
      returnsNormally,
    );
  });
}
