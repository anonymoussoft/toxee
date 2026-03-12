import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Centralized SnackBar helper with consistent styling.
class AppSnackBar {
  AppSnackBar._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final brightness = Theme.of(context).brightness;
    Color? backgroundColor;
    if (isError) {
      backgroundColor = AppThemeConfig.errorColor;
    } else if (isSuccess) {
      backgroundColor = brightness == Brightness.dark
          ? AppThemeConfig.primaryColorDark
          : AppThemeConfig.primaryColor;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: (isError || isSuccess) ? Colors.white : null,
            ),
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          margin: const EdgeInsets.all(AppSpacing.lg),
          duration: isError ? const Duration(seconds: 4) : duration,
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                  textColor: Colors.white,
                )
              : null,
        ),
      );
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true);
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, isSuccess: true);
  }
}
