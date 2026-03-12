import 'package:flutter/material.dart';
import '../util/responsive_layout.dart';

/// Business-dark background color for call surfaces (near-black graphite).
const Color kCallBackgroundBase = Color(0xFF1A1A1A);

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
      mobile: 16,
      tablet: 20,
      desktop: 24,
    );
    final horizontalPadding =
        ResponsiveLayout.responsiveHorizontalPadding(context);

    return Container(
      color: kCallBackgroundBase,
      child: SafeArea(
        child: Column(
          children: [
            if (topBar != null)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: topBarHeight),
                child: topBar!,
              ),
            Expanded(child: child),
            if (bottomBar != null) ...[
              SizedBox(height: bottomPadding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: bottomBar!,
              ),
              SizedBox(height: bottomPadding),
            ],
          ],
        ),
      ),
    );
  }
}
