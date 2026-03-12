import 'package:flutter/material.dart';
import 'prefs.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> initFromPrefs() async {
    final m = await Prefs.getThemeMode();
    mode.value = (m == 'dark') ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await Prefs.setThemeMode(m == ThemeMode.dark ? 'dark' : 'light');
  }
}


