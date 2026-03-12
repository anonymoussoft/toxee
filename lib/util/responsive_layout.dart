import 'package:flutter/material.dart';

/// Responsive layout utility class
/// Provides helper methods for creating responsive layouts that adapt to
/// different screen sizes (mobile, tablet, desktop)
class ResponsiveLayout {
  // Breakpoints for different device types
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  /// Check if current screen is mobile size
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  /// Check if current screen is tablet size
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  /// Check if current screen is desktop size
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  /// Get responsive value based on screen size
  /// 
  /// Returns the appropriate value for the current screen size:
  /// - mobile: value for mobile screens (< 600px)
  /// - tablet: value for tablet screens (600px - 1024px)
  /// - desktop: value for desktop screens (> 1024px)
  /// 
  /// If a value is not provided for a specific size, it will fall back to:
  /// desktop -> tablet -> mobile
  static T responsiveValue<T>(
    BuildContext context, {
    T? mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) {
      return desktop;
    } else if (isTablet(context) && tablet != null) {
      return tablet;
    } else if (isMobile(context) && mobile != null) {
      return mobile;
    }
    // Fallback chain: desktop -> tablet -> mobile
    return desktop ?? tablet ?? mobile ?? (throw ArgumentError('At least one value must be provided'));
  }

  /// Get responsive padding based on screen size
  static EdgeInsets responsivePadding(BuildContext context) {
    return responsiveValue<EdgeInsets>(
      context,
      mobile: const EdgeInsets.all(8.0),
      tablet: const EdgeInsets.all(16.0),
      desktop: const EdgeInsets.all(24.0),
    );
  }

  /// Get responsive horizontal padding
  static double responsiveHorizontalPadding(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 8.0,
      tablet: 16.0,
      desktop: 24.0,
    );
  }

  /// Get responsive vertical padding
  static double responsiveVerticalPadding(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 8.0,
      tablet: 16.0,
      desktop: 24.0,
    );
  }

  /// Get responsive column count for grid layouts
  static int responsiveColumnCount(BuildContext context) {
    return responsiveValue<int>(
      context,
      mobile: 1,
      tablet: 2,
      desktop: 3,
    );
  }

  /// Get responsive font size multiplier
  static double responsiveFontSize(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 1.0,
      tablet: 1.1,
      desktop: 1.2,
    );
  }

  /// Get responsive max width for content containers
  static double? responsiveMaxWidth(BuildContext context) {
    return responsiveValue<double?>(
      context,
      mobile: null, // Full width on mobile
      tablet: 800.0,
      desktop: 1200.0,
    );
  }

  /// Get responsive sidebar width
  /// Mobile: 0 (uses Drawer instead of permanent sidebar)
  /// Tablet: 80 (compact icon sidebar)
  /// Desktop: 100 (icon + label sidebar)
  static double responsiveSidebarWidth(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 0.0, // No sidebar on mobile, uses Drawer
      tablet: 80.0,
      desktop: 100.0,
    );
  }

  /// Get responsive bottom navigation bar height
  static double responsiveBottomNavHeight(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 56.0, // Standard bottom nav height
      tablet: 0.0, // No bottom nav on tablet/desktop
      desktop: 0.0,
    );
  }

  /// Check if should show bottom navigation
  static bool shouldShowBottomNav(BuildContext context) {
    return isMobile(context);
  }

  /// Check if should show sidebar
  static bool shouldShowSidebar(BuildContext context) {
    return isTablet(context) || isDesktop(context);
  }

  /// Get responsive icon size
  static double responsiveIconSize(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 24.0,
      tablet: 28.0,
      desktop: 32.0,
    );
  }
}

