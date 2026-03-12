import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../util/app_theme_config.dart';
import '../util/prefs.dart';

/// Shown when stored preferences were saved by a newer app version.
/// Prompts the user to upgrade the app and does not overwrite their data.
class UpgradeRequiredApp extends StatelessWidget {
  const UpgradeRequiredApp({
    super.key,
    required this.storedVersion,
    required this.currentVersion,
  });

  final int storedVersion;
  final int currentVersion;

  static ThemeData get _lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: AppThemeConfig.primaryColor,
        scaffoldBackgroundColor: AppThemeConfig.lightScaffoldBackground,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          elevation: 1,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
        ),
      );

  static ThemeData get _darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: AppThemeConfig.primaryColorDark,
        scaffoldBackgroundColor: AppThemeConfig.darkScaffoldBackground,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          elevation: 1,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Prefs.getThemeMode(),
      builder: (context, snapshot) {
        final themeMode = snapshot.data == 'dark' ? ThemeMode.dark : ThemeMode.light;
        return MaterialApp(
          title: 'toxee',
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UpgradeRequiredScreen(
            storedVersion: storedVersion,
            currentVersion: currentVersion,
          ),
        );
      },
    );
  }
}

class UpgradeRequiredScreen extends StatelessWidget {
  const UpgradeRequiredScreen({
    super.key,
    required this.storedVersion,
    required this.currentVersion,
  });

  final int storedVersion;
  final int currentVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                l10n.upgradeRequiredTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.upgradeRequiredMessage(storedVersion, currentVersion),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
