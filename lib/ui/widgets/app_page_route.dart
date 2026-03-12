import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Custom page route with platform-aware transitions.
/// Mobile: slide from right + fade. Desktop: fade only.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: _buildTransition,
          transitionDuration: _isMobilePlatform
              ? const Duration(milliseconds: 250)
              : const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
        );

  static bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Widget _buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    if (_isMobilePlatform) {
      // Mobile: subtle slide from right + fade
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    }
    // Desktop/tablet: fade only
    return FadeTransition(opacity: curved, child: child);
  }
}
