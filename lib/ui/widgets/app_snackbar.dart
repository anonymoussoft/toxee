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
    bool isInfo = false,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    Color? backgroundColor;
    Color? foregroundColor;
    if (isError) {
      backgroundColor = AppThemeConfig.errorColor;
      foregroundColor = Colors.white;
    } else if (isSuccess) {
      // Success uses the dedicated success token (emerald) — was previously
      // using the primary brand color, which conflated "this happened" with
      // "this is the brand action".
      backgroundColor = AppThemeConfig.successColor;
      foregroundColor = Colors.white;
    } else if (isInfo) {
      // Slate-tinted neutral surface for informational messages.
      backgroundColor =
          AppThemeConfig.secondaryTextColorLight.withValues(alpha: 0.12);
      foregroundColor = Theme.of(context).colorScheme.onSurface;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: foregroundColor),
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
                  textColor: foregroundColor ?? Colors.white,
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

  static void showInfo(BuildContext context, String message) {
    show(context, message, isInfo: true);
  }
}
