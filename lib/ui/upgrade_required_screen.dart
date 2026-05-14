import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
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
          // Flat surface + hairline border, matches the rest of the app.
          elevation: 0,
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
          // Flat surface + hairline border, matches the rest of the app.
          elevation: 0,
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
          title: 'Toxee',
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tinted-primary chip for the status icon — same visual
                  // language as the primary action card on the login page.
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.08),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  AppSpacing.verticalXl,
                  Text(
                    l10n.upgradeRequiredTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalMd,
                  Text(
                    l10n.upgradeRequiredMessage(storedVersion, currentVersion),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
