import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

// 4pt matches AppSpacing.xs grid — keeps skeleton bars aligned to the
// same rhythm as live content.
const double _kSkeletonRadius = 4.0;

/// A skeleton/shimmer loading placeholder for lists.
/// Uses pure Flutter animations without external packages.
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 64.0,
  });

  final int itemCount;
  final double itemHeight;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Token-derived shimmer palette:
    //   dark  base = othersMessageBubbleColorDark (slate-800, our surface-1)
    //   dark  highlight = base lerped 20% toward the slate-400 secondary
    //                     text color — gives a perceptible shimmer band
    //                     without introducing a new color token.
    //   light base = dividerColorLight (slate-200 / cool blue tint, our
    //                hairline divider; reads as a "muted surface").
    //   light highlight = base lerped 50% toward white — softer than the
    //                     old slate-50 hex but still clearly above base.
    final baseColor = isDark
        ? AppThemeConfig.othersMessageBubbleColorDark
        : AppThemeConfig.dividerColorLight;
    final highlightColor = isDark
        ? Color.lerp(
            AppThemeConfig.othersMessageBubbleColorDark,
            AppThemeConfig.secondaryTextColorDark,
            0.20,
          )!
        : Color.lerp(
            AppThemeConfig.dividerColorLight,
            Colors.white,
            0.50,
          )!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Column(
          children: List.generate(widget.itemCount, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: SizedBox(
                height: widget.itemHeight,
                child: Row(
                  children: [
                    // Avatar placeholder
                    _ShimmerBox(
                      width: 48,
                      height: 48,
                      isCircle: true,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                      progress: _controller.value,
                    ),
                    AppSpacing.horizontalMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title placeholder
                          _ShimmerBox(
                            width: double.infinity,
                            height: 14,
                            baseColor: baseColor,
                            highlightColor: highlightColor,
                            progress: _controller.value,
                            widthFraction: 0.6 + (index % 3) * 0.1,
                          ),
                          AppSpacing.verticalSm,
                          // Subtitle placeholder
                          _ShimmerBox(
                            width: double.infinity,
                            height: 10,
                            baseColor: baseColor,
                            highlightColor: highlightColor,
                            progress: _controller.value,
                            widthFraction: 0.4 + (index % 2) * 0.2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    this.isCircle = false,
    this.widthFraction = 1.0,
  });

  final double width;
  final double height;
  final Color baseColor;
  final Color highlightColor;
  final double progress;
  final bool isCircle;
  final double widthFraction;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      baseColor,
      highlightColor,
      (0.5 + 0.5 * (progress * 2 - 1).abs()).clamp(0.0, 1.0),
    )!;
    return FractionallySizedBox(
      widthFactor: isCircle ? null : widthFraction,
      child: Container(
        width: isCircle ? width : null,
        height: height,
        decoration: BoxDecoration(
          color: color,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(_kSkeletonRadius),
        ),
      ),
    );
  }
}
