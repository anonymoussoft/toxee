import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// The weak→strong password-strength bar shown under the password field on the
/// register page. Extracted from `register_page.dart` so that page stays under
/// the 500-LOC complexity cap. Pure presentation: it derives the strength from
/// [password] and renders four segments.
///
/// Test keys (read by
/// `test/ui/register/register_password_strength_real_ui_test.dart`):
///   - `register_password_strength_bar` on the container
///   - `register_strength_segment_<i>` on each segment (filled iff i < strength)
class RegisterPasswordStrengthBar extends StatelessWidget {
  const RegisterPasswordStrengthBar({super.key, required this.password});

  final String password;

  /// 0 (empty) … 4 (strong). Public + visible so a unit test can assert the
  /// ramp directly without rebuilding the widget.
  static int strengthOf(String password) {
    if (password.isEmpty) return 0;
    if (password.length < 6) return 1;
    int score = 2;
    if (password.length >= 8 &&
        (RegExp(r'[A-Z]').hasMatch(password) ||
            RegExp(r'\d').hasMatch(password))) {
      score = 3;
    }
    if (password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[!@#$%^&*]').hasMatch(password)) {
      score = 4;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final strength = strengthOf(password);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Decorative semantic ramp: weak → strong. The two middle segments are
    // status colors (amber-500 / amber-300 from the design system) and are
    // intentionally kept hex — they live alongside cs.error and cs.primary
    // as a visual gradient, not a themed brand surface.
    final colors = [
      cs.error,
      AppThemeConfig.statusAwayColor, // amber-500
      const Color(0xFFFCD34D), // amber-300 (lighter than statusAway)
      cs.primary,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      // Stable test key for the password-strength bar (real-UI gate reads its
      // per-segment fill state to assert weak→strong ramping).
      key: const Key('register_password_strength_bar'),
      child: Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: AnimatedContainer(
              // Per-segment stable key: `register_strength_segment_<i>`. A
              // segment is "filled" when its BoxDecoration.color == colors[i]
              // (i < strength) and "empty" (outline @ alpha 0.2) otherwise.
              // Tests count filled segments to verify the 0→4 strength ramp.
              key: Key('register_strength_segment_$i'),
              duration: reduceMotion ? Duration.zero : AppDurations.medium,
              curve: AppCurves.standard,
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? AppSpacing.xs : 0),
              decoration: BoxDecoration(
                color: i < strength
                    ? colors[i]
                    : cs.outline.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
