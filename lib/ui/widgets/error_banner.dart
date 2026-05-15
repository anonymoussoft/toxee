import 'package:flutter/material.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../../util/app_spacing.dart';

/// A styled inline error banner with optional retry button.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Live region announces the error to screen readers when the banner
      // appears or its message updates.
      liveRegion: true,
      container: true,
      label: AppLocalizations.of(context)?.errorBannerLabel(message) ?? 'Error: $message',
      child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppThemeConfig.errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppThemeConfig.errorColor,
            size: 20,
          ),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppThemeConfig.errorColor,
                  ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppThemeConfig.errorColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppThemeConfig.errorColor),
              onPressed: onDismiss,
              // 44x44 minimum tap area for mobile (Apple HIG / Material 48dp).
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      ),
    );
  }
}
