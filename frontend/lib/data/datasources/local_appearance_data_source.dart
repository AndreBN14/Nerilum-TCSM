import 'package:shared_preferences/shared_preferences.dart';

// Única preferencia persistente del prototipo; las cuentas siguen en memoria.
class LocalAppearanceDataSource {
  const LocalAppearanceDataSource();

  static const _key = 'nerilum_light_mode';

  Future<bool> loadLightMode() async =>
      await SharedPreferencesAsync().getBool(_key) ?? false;

  Future<void> saveLightMode(bool light) =>
      SharedPreferencesAsync().setBool(_key, light);
}
