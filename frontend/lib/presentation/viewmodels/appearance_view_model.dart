import 'package:flutter/foundation.dart';

import '../../domain/models/appearance.dart';
import '../../domain/usecases/appearance_use_cases.dart';

class AppearanceViewModel extends ChangeNotifier {
  AppearanceViewModel({
    required this.loadAppearance,
    required this.saveAppearance,
    this.appearance = AppAppearance.dark,
  });

  final LoadAppearance loadAppearance;
  final SaveAppearance saveAppearance;
  AppAppearance appearance;

  Future<void> load() async {
    try {
      appearance = await loadAppearance();
      notifyListeners();
    } catch (_) {
      // Sin una preferencia guardada se conserva el modo oscuro.
    }
  }

  Future<bool> setAppearance(AppAppearance value) async {
    if (appearance == value) return true;
    final previous = appearance;
    appearance = value;
    notifyListeners();
    try {
      await saveAppearance(value);
      return true;
    } catch (_) {
      appearance = previous;
      notifyListeners();
      return false;
    }
  }
}
