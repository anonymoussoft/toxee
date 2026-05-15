import 'package:flutter/material.dart';
import 'prefs.dart';

class AppTheme {
  /// Current app theme mode. Defaults to [ThemeMode.system] on first launch
  /// (follow OS); resolves from prefs in [initFromPrefs].
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> initFromPrefs() async {
    final m = await Prefs.getThemeMode();
    switch (m) {
      case 'dark':
        mode.value = ThemeMode.dark;
        break;
      case 'light':
        mode.value = ThemeMode.light;
        break;
      case 'system':
      default:
        mode.value = ThemeMode.system;
        break;
    }
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final serialized = switch (m) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await Prefs.setThemeMode(serialized);
  }
}


