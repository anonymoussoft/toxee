import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';

/// Slate-900 base background for call surfaces — aliased to the shared
/// `AppThemeConfig.darkScaffoldBackground` token so the call screen reads as a
/// continuation of the app, not a separate aesthetic.
const Color kCallBackgroundBase = AppThemeConfig.darkScaffoldBackground;

/// Shared page shell for all call screens: dark surface, safe area, top bar, content, bottom dock.
class CallSceneShell extends StatelessWidget {
  const CallSceneShell({
    super.key,
    required this.child,
    this.topBar,
    this.bottomBar,
  });

  final Widget child;
  final Widget? topBar;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final topBarHeight = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: 56,
      tablet: 64,
      desktop: 72,
    );
    final bottomPadding = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: AppSpacing.lg,
      tablet: AppSpacing.xl,
      desktop: AppSpacing.xl,
    );
    final horizontalPadding =
        ResponsiveLayout.responsiveHorizontalPadding(context);

    // Video must reach the screen edges (so video calls don't render with
    // black bars under notch / home-indicator), while topBar + bottomBar
    // still respect the safe-area insets. We use a Stack: the child renders
    // edge-to-edge as the base layer, then topBar/bottomBar are pinned to
    // the top/bottom and wrapped in single-edge SafeArea so the controls
    // don't get clipped by hardware cutouts.
    final mediaPadding = MediaQuery.paddingOf(context);

    return Container(
      color: kCallBackgroundBase,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base layer: child renders edge-to-edge. For video calls this is
          // the video stage; for identity (audio) calls it's the avatar card
          // which already centers within the available space, so reaching
          // the edges just means the slate-900 backdrop extends all the way.
          Positioned.fill(
            // Pad the child by the topBar height + safe-area top, the
            // bottomBar block + safe-area bottom, AND horizontal safe-area
            // insets so content (avatar, video stage) doesn't underflow
            // behind hardware cutouts in landscape (notch on iPhone, etc.).
            // The *background* (parent Container) still reaches the screen
            // edges so video bleeds behind the notch as expected — only the
            // *content* avoids it.
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                mediaPadding.left,
                topBar != null ? topBarHeight + mediaPadding.top : 0,
                mediaPadding.right,
                bottomBar != null
                    ? mediaPadding.bottom + bottomPadding * 2
                    : 0,
              ),
              child: child,
            ),
          ),
          if (topBar != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: topBarHeight),
                  child: topBar!,
                ),
              ),
            ),
          if (bottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: bottomPadding),
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: bottomBar!,
                    ),
                    SizedBox(height: bottomPadding),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
