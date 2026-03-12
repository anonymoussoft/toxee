import 'dart:io';
import 'package:flutter/foundation.dart';

/// Device type enumeration
enum DeviceType {
  mobile,
  tablet,
  desktop,
}

/// Platform utility class for detecting platform and device types
class PlatformUtils {
  /// Check if running on desktop platform
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Check if running on mobile platform
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Check if running on macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// Check if running on Linux
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Check if running on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Check if running on Android
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Check if running on iOS
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Get the current operating system name
  static String get operatingSystem => Platform.operatingSystem;

  /// Get device type based on platform
  /// Note: This is a basic implementation. For more accurate tablet detection,
  /// use ResponsiveLayout with MediaQuery
  static DeviceType get deviceType {
    if (isMobile) {
      return DeviceType.mobile;
    } else if (isDesktop) {
      return DeviceType.desktop;
    } else {
      // Default to mobile for unknown platforms
      return DeviceType.mobile;
    }
  }

  /// Get platform-specific library extension
  static String get libraryExtension {
    if (Platform.isMacOS || Platform.isIOS) {
      return '.dylib';
    } else if (Platform.isLinux || Platform.isAndroid) {
      return '.so';
    } else if (Platform.isWindows) {
      return '.dll';
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Get platform-specific library name prefix
  static String get libraryPrefix {
    if (Platform.isWindows) {
      return ''; // Windows DLLs don't have 'lib' prefix
    } else {
      return 'lib'; // Unix-like systems use 'lib' prefix
    }
  }

  /// Get platform-specific library name for tim2tox_ffi
  static String get tim2toxFfiLibraryName {
    final prefix = libraryPrefix;
    final ext = libraryExtension;
    return '${prefix}tim2tox_ffi$ext';
  }
}

