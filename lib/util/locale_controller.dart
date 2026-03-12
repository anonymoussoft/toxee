import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

class AppLocale {
  static final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  static Future<void> initFromPrefs() async {
    final saved = await Prefs.getLocale();
    locale.value = saved ?? _resolveSystemLocale();
  }

  /// Resolves system locale to a supported one; falls back to English if not supported.
  static Locale _resolveSystemLocale() {
    final system = PlatformDispatcher.instance.locale;
    const supportedCodes = ['ar', 'en', 'ja', 'ko', 'zh'];
    if (!supportedCodes.contains(system.languageCode)) {
      return const Locale('en');
    }
    if (system.languageCode == 'zh') {
      if (system.scriptCode == 'Hant') {
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      }
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    }
    return Locale(system.languageCode);
  }

  static Future<void> set(Locale l) async {
    locale.value = l;
    await Prefs.setLocale(l);
  }
}


