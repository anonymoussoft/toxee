import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import '../startup/startup_step.dart';

/// Step metadata: icon, progress fraction, and localized message getter.
typedef _StepMeta = ({
  IconData icon,
  double progress,
  String Function(AppLocalizations l10n) message,
});

const _kStepCount = 7; // excludes 'completed'

/// Ordered list of active steps (excluding completed) for dot indicators.
const _kActiveSteps = [
  StartupStep.checkingUserInfo,
  StartupStep.initializingService,
  StartupStep.loggingIn,
  StartupStep.initializingSDK,
  StartupStep.updatingProfile,
  StartupStep.connecting,
  StartupStep.loadingFriends,
];

final Map<StartupStep, _StepMeta> _stepMeta = {
  StartupStep.checkingUserInfo: (
    icon: Icons.person_outline,
    progress: 1 / _kStepCount,
    message: (l) => l.checkingUserInfo,
  ),
  StartupStep.initializingService: (
    icon: Icons.settings_outlined,
    progress: 2 / _kStepCount,
    message: (l) => l.initializingService,
  ),
  StartupStep.loggingIn: (
    icon: Icons.login,
    progress: 3 / _kStepCount,
    message: (l) => l.loggingIn,
  ),
  StartupStep.initializingSDK: (
    icon: Icons.code,
    progress: 4 / _kStepCount,
    message: (l) => l.initializingSDK,
  ),
  StartupStep.updatingProfile: (
    icon: Icons.edit_outlined,
    progress: 5 / _kStepCount,
    message: (l) => l.updatingProfile,
  ),
  StartupStep.connecting: (
    icon: Icons.lock_outline,
    progress: 6 / _kStepCount,
    message: (l) => l.establishingEncryptedChannel,
  ),
  StartupStep.loadingFriends: (
    icon: Icons.people_outline,
    progress: 7 / _kStepCount,
    message: (l) => l.loadingFriends,
  ),
  StartupStep.completed: (
    icon: Icons.check_circle,
    progress: 1.0,
    message: (l) => l.initializationCompleted,
  ),
};

class StartupLoadingScreen extends StatefulWidget {
  final StartupStep currentStep;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onGoToLogin;

  const StartupLoadingScreen({
    super.key,
    required this.currentStep,
    this.errorMessage,
    this.onRetry,
    this.onGoToLogin,
  });

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _progressAnimation;
  double _previousProgress = 0.0;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Slide animation for step text
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _slideController.forward();

    // Smooth progress animation
    final initialProgress = _stepMeta[widget.currentStep]!.progress;
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: initialProgress)
        .animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));
    _previousProgress = initialProgress;
    _progressController.forward();
  }

  @override
  void didUpdateWidget(StartupLoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStep != widget.currentStep) {
      // Animate progress bar to new value
      final newProgress = _stepMeta[widget.currentStep]!.progress;
      _progressAnimation = Tween<double>(
        begin: _previousProgress,
        end: newProgress,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ));
      _previousProgress = newProgress;
      _progressController
        ..reset()
        ..forward();

      // Slide animation for step text
      _slideController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    if (l10n == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: _buildBackground(
        isDark: isDark,
        child: widget.errorMessage != null
            ? _buildErrorContent(theme, l10n)
            : _buildLoadingContent(theme, l10n, isDark),
      ),
    );
  }

  Widget _buildBackground({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppThemeConfig.darkGradientStart,
                  AppThemeConfig.darkGradientEnd,
                ]
              : [
                  AppThemeConfig.lightGradientStart,
                  AppThemeConfig.lightGradientEnd,
                ],
        ),
      ),
      child: SafeArea(child: child),
    );
  }

  Widget _buildLoadingContent(
      ThemeData theme, AppLocalizations l10n, bool isDark) {
    final primaryColor = theme.colorScheme.primary;
    final meta = _stepMeta[widget.currentStep]!;
    final currentIndex = _kActiveSteps.indexOf(widget.currentStep);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxHeight < 500;
        final iconSize = isSmall ? 80.0 : 100.0;
        final iconInnerSize = isSmall ? 40.0 : 50.0;
        final hPadding = ResponsiveLayout.responsiveValue<double>(
          context,
          mobile: 32.0,
          tablet: 60.0,
          desktop: 80.0,
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing icon
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withValues(alpha: 0.1),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      meta.icon,
                      size: iconInnerSize,
                      color: primaryColor,
                    ),
                  ),
                ),
                SizedBox(height: isSmall ? 32 : 48),

                // Step message with slide + fade animation
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _slideController,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Text(
                        meta.message(l10n),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isSmall ? 24 : 32),

                // Animated progress bar + percentage
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: _buildAnimatedProgressBar(theme, primaryColor),
                ),
                SizedBox(height: isSmall ? 16 : 24),

                // Step dot indicators
                _buildStepDots(theme, primaryColor, currentIndex),
                SizedBox(height: isSmall ? 32 : 48),

                // App name
                Text(
                  'Toxee',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedProgressBar(ThemeData theme, Color primaryColor) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        final value = _progressAnimation.value;
        return Column(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(AppThemeConfig.inputBorderRadius),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(value * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepDots(
      ThemeData theme, Color primaryColor, int currentIndex) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_kStepCount, (i) {
        final isActive = i <= currentIndex;
        final isCurrent = i == currentIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isCurrent ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive
                  ? primaryColor
                  : theme.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildErrorContent(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.startupFailed,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.errorMessage ?? l10n.unknownError,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            if (widget.onRetry != null)
              ElevatedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                  ),
                ),
              ),
            if (widget.onRetry != null && widget.onGoToLogin != null)
              const SizedBox(height: 12),
            if (widget.onGoToLogin != null)
              OutlinedButton.icon(
                onPressed: widget.onGoToLogin,
                icon: const Icon(Icons.login),
                label: Text(l10n.goToLogin),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
