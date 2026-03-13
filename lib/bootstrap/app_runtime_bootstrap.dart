import 'package:flutter/material.dart';

import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';

import '../util/app_theme_config.dart';
import '../util/locale_controller.dart';
import '../util/logger.dart';
import '../util/theme_controller.dart';

/// Theme, locale, and UIKit theme initialization.
class AppRuntimeBootstrap {
  AppRuntimeBootstrap._();

  static Future<void> initialize() async {
    AppLogger.log('Initializing theme and locale...');
    await AppTheme.initFromPrefs();
    await AppLocale.initFromPrefs();
    TencentCloudChatTheme.init(
      themeModel: AppThemeConfig.createYouthfulThemeModel(),
      brightness: AppTheme.mode.value == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light,
    );
    AppLogger.log('Theme and locale initialized');
  }
}
