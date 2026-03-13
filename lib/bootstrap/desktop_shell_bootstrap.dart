import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../util/app_tray.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';

class _WindowStateListener with WindowListener {
  @override
  void onWindowClose() async {
    try {
      final bounds = await windowManager.getBounds();
      await Prefs.setWindowBounds(bounds);
      final maximized = await windowManager.isMaximized();
      await Prefs.setWindowMaximized(maximized);
    } catch (e, stackTrace) {
      AppLogger.warn('Failed to persist window state before close: $e');
      AppLogger.logError(
        'Window state persistence error during onWindowClose',
        e,
        stackTrace,
      );
    }
    await windowManager.destroy();
  }
}

/// Window manager and tray initialization (desktop only).
class DesktopShellBootstrap {
  DesktopShellBootstrap._();

  static Future<void> initializeIfNeeded() async {
    if (!PlatformUtils.isDesktop) return;
    if (!AppTray.instance.isSupported) return;

    await windowManager.ensureInitialized();
    const minSize = Size(960, 600);
    await windowManager.setMinimumSize(minSize);
    const defaultSize = Size(1280, 800);
    const windowOptions = WindowOptions(
      size: defaultSize,
      minimumSize: minSize,
      title: 'Toxee',
      center: true,
    );

    final savedBounds = await Prefs.getWindowBounds();
    final savedMaximized = await Prefs.getWindowMaximized();
    final validBounds = savedBounds != null &&
        savedBounds.width >= minSize.width &&
        savedBounds.height >= minSize.height &&
        savedBounds.width <= 4096 &&
        savedBounds.height <= 4096;

    windowManager.addListener(_WindowStateListener());
    await windowManager.setPreventClose(true);

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (validBounds) {
        try {
          await windowManager.setBounds(savedBounds);
        } catch (e) {
          AppLogger.warn('Could not restore window bounds: $e');
        }
      }
      await windowManager.show();
      await windowManager.focus();
      if (savedMaximized) {
        try {
          await windowManager.maximize();
        } catch (e) {
          AppLogger.warn('Could not maximize window: $e');
        }
      }
    });
    await AppTray.instance.init();
  }
}
