// L1 test (scenario S7 / roadmap "theme persistence across cold restart").
//
// Locks the contract that the chosen theme mode survives a cold restart.
// This is a pure Dart + Prefs test: it exercises only [Prefs] theme-mode
// accessors and the [AppTheme] controller, both of which touch nothing but
// SharedPreferences. No FfiChatService, no widget pump, no FFI dylib — so
// there is no native skip-guard.
//
// "Cold restart" is simulated by resetting [AppTheme.mode] back to its
// first-launch default (ThemeMode.system) and re-running [initFromPrefs],
// which is exactly what main() does on a fresh process start: the static
// ValueNotifier is born at ThemeMode.system, then loads the persisted value.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    // Reset the static controller to its first-launch default so each test
    // starts from a clean "cold" baseline.
    AppTheme.mode.value = ThemeMode.system;
  });

  group('Prefs theme-mode round-trip', () {
    test('defaults to "system" when unset', () async {
      expect(
        await Prefs.getThemeMode(),
        'system',
        reason: 'first launch (no stored value) must follow the OS preference',
      );
    });

    test('persists and reads back "dark"', () async {
      await Prefs.setThemeMode('dark');
      expect(
        await Prefs.getThemeMode(),
        'dark',
        reason: 'setThemeMode("dark") must round-trip through Prefs',
      );
    });

    test('persists and reads back "light"', () async {
      await Prefs.setThemeMode('light');
      expect(
        await Prefs.getThemeMode(),
        'light',
        reason: 'setThemeMode("light") must round-trip through Prefs',
      );
    });

    test('persists and reads back "system"', () async {
      // Write a non-default first so we know "system" is actually stored,
      // not just falling through to the default.
      await Prefs.setThemeMode('dark');
      await Prefs.setThemeMode('system');
      expect(
        await Prefs.getThemeMode(),
        'system',
        reason: 'setThemeMode("system") must overwrite a prior value',
      );
    });

    test('coerces an unknown value to "system"', () async {
      await Prefs.setThemeMode('chartreuse');
      expect(
        await Prefs.getThemeMode(),
        'system',
        reason: 'unknown values must be normalized to "system"',
      );
    });
  });

  group('AppTheme controller cold-restart persistence', () {
    // Maps each persisted Prefs string to the ThemeMode the controller must
    // resolve to after a cold restart.
    const cases = <String, ThemeMode>{
      'dark': ThemeMode.dark,
      'light': ThemeMode.light,
      'system': ThemeMode.system,
    };

    for (final entry in cases.entries) {
      final stored = entry.key;
      final expectedMode = entry.value;
      final modeForSet = switch (stored) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };

      test('"$stored" survives a simulated cold restart', () async {
        // 1. User picks a mode through the controller.
        await AppTheme.set(modeForSet);
        expect(
          AppTheme.mode.value,
          expectedMode,
          reason: 'AppTheme.set must update the live notifier immediately',
        );

        // 2. The choice must be persisted to Prefs.
        expect(
          await Prefs.getThemeMode(),
          stored,
          reason: 'AppTheme.set("$modeForSet") must persist "$stored" to Prefs',
        );

        // 3. Simulate a cold restart: a fresh process starts with the static
        //    notifier at its first-launch default before initFromPrefs runs.
        AppTheme.mode.value = ThemeMode.system;

        // 4. Loading from prefs (as main() does) must restore the choice.
        await AppTheme.initFromPrefs();
        expect(
          AppTheme.mode.value,
          expectedMode,
          reason:
              'after cold restart, initFromPrefs must restore "$stored" '
              '($expectedMode), not the default',
        );
      });
    }

    test('cold start with no stored value resolves to ThemeMode.system',
        () async {
      // Nothing persisted; first launch on a fresh device.
      await AppTheme.initFromPrefs();
      expect(
        AppTheme.mode.value,
        ThemeMode.system,
        reason: 'first launch with empty Prefs must follow the OS (system)',
      );
    });

    test('a later cold start reflects the most recent persisted choice',
        () async {
      // First the user prefers dark...
      await AppTheme.set(ThemeMode.dark);
      AppTheme.mode.value = ThemeMode.system; // cold restart
      await AppTheme.initFromPrefs();
      expect(AppTheme.mode.value, ThemeMode.dark,
          reason: 'restart should restore the dark choice');

      // ...then switches to light; the next restart must honor light.
      await AppTheme.set(ThemeMode.light);
      AppTheme.mode.value = ThemeMode.system; // cold restart
      await AppTheme.initFromPrefs();
      expect(
        AppTheme.mode.value,
        ThemeMode.light,
        reason: 'the latest persisted choice (light) must win after restart',
      );
    });
  });
}
