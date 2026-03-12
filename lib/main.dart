import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'util/app_paths.dart';
import 'ui/widgets/app_page_route.dart';
import 'package:tencent_cloud_chat_common/widgets/material_app.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'ui/login_page.dart';
import 'ui/home_page.dart';
import 'ui/startup_loading_screen.dart';
import 'ui/upgrade_required_screen.dart';
import 'util/prefs_upgrader.dart';
import 'sdk_fake/fake_uikit_core.dart';
import 'util/prefs.dart';
import 'util/theme_controller.dart';
import 'util/locale_controller.dart';
import 'i18n/app_localizations.dart';
import 'util/app_tray.dart';
import 'util/logger.dart';
import 'util/platform_utils.dart';
import 'adapters/logger_adapter.dart';
import 'call/call_overlay.dart';
import 'call/call_effects_listener.dart';
import 'adapters/shared_prefs_adapter.dart';
import 'adapters/bootstrap_adapter.dart';
import 'util/bootstrap_nodes.dart';
import 'util/app_theme_config.dart';
import 'util/account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

/// Routes print() output to AppLogger. Parses TCCF lines (TencentCloudChatLog)
/// so level and body are normalized instead of duplicating timestamp in body.
void _routePrintToLogger(String line) {
  // TCCF:2026-02-11 03:48:47 PM:TencentCloudChatMessageSDK:debug:{ addUIKitListener 1770796127319 }
  final tccfMatch = RegExp(
          r'^TCCF:(?:\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2} [AP]M):([^:]+):(debug|info|error|all):\{ (.*) \}$')
      .firstMatch(line);
  if (tccfMatch != null) {
    final component = tccfMatch.group(1)!.trim();
    final level = tccfMatch.group(2)!;
    final body = tccfMatch.group(3)!.trim();
    final logBody = '$component: $body';
    switch (level) {
      case 'debug':
        AppLogger.debug(logBody);
        break;
      case 'info':
        AppLogger.info(logBody);
        break;
      case 'error':
        AppLogger.error(logBody);
        break;
      case 'all':
      default:
        AppLogger.info(logBody);
    }
    return;
  }
  AppLogger.info(line);
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Set log file path to build/flutter_client.log (relative to app directory)
      // This matches the path used in run_toxee.sh
      // The script sets TOXEE_LOG_DIR environment variable
      // NOTE: Due to macOS sandbox restrictions, we may not be able to write to project directory
      // In that case, we'll use application support directory and create a symlink
      try {
        String? logPath;
        bool useSymlink = false;

        // Try 1: Use environment variable set by run_toxee.sh
        final logDirEnv = Platform.environment['TOXEE_LOG_DIR'];
        if (logDirEnv != null && logDirEnv.isNotEmpty) {
          final testPath = '$logDirEnv/flutter_client.log';
          // Try to write a test file to check if we have permission
          try {
            final testFile = File(testPath);
            final testDir = testFile.parent;
            if (!testDir.existsSync()) {
              testDir.createSync(recursive: true);
            }
            // Try to write a test byte
            testFile.writeAsStringSync('test', mode: FileMode.write);
            testFile.deleteSync();
            // If we get here, we have write permission
            logPath = testPath;
            stderr.writeln(
                'AppLogger: Using log directory from environment: $logDirEnv');
          } catch (e) {
            // No write permission to project directory (expected in macOS sandbox), will use symlink approach
            stderr.writeln(
                'AppLogger: [INFO] Cannot write to project directory due to sandbox restrictions (expected): $logDirEnv');
            stderr.writeln(
                'AppLogger: [INFO] Will use application support directory and create symlink');
            useSymlink = true;
          }
        }

        // Try 2: Use Directory.current (works when run from script, not in app bundle)
        if (logPath == null && !useSymlink) {
          try {
            final currentDir = Directory.current;
            final testPath = '${currentDir.path}/build/flutter_client.log';
            final testFile = File(testPath);
            final testDir = testFile.parent;
            // Check if build directory exists or can be created
            if (testDir.existsSync() || testDir.parent.existsSync()) {
              // Try to write a test file
              try {
                testFile.writeAsStringSync('test', mode: FileMode.write);
                testFile.deleteSync();
                logPath = testPath;
                stderr.writeln(
                    'AppLogger: Using Directory.current: ${currentDir.path}');
              } catch (e) {
                stderr.writeln(
                    'AppLogger: Cannot write to Directory.current: $e');
                useSymlink = true;
              }
            }
          } catch (e) {
            // Directory.current might not work in app bundle
          }
        }

        // Try 3: Use application support directory (always works in sandbox)
        if (logPath == null || useSymlink) {
          try {
            logPath = await AppPaths.logFilePath;
            stderr.writeln(
                'AppLogger: Using application support directory: ${await AppPaths.applicationSupportPath}');

            // Note: We cannot create symlink from sandboxed app to project directory
            // The script (run_toxee.sh) will create the symlink after app starts
            // Just log the actual location for reference
            if (useSymlink && logDirEnv != null && logDirEnv.isNotEmpty) {
              stderr.writeln(
                  'AppLogger: [INFO] Cannot create symlink from sandbox (expected - macOS security restriction)');
              stderr.writeln('AppLogger: [INFO] Logs will be in: $logPath');
              stderr.writeln(
                  'AppLogger: [INFO] Script will create symlink: $logDirEnv/flutter_client.log -> $logPath');
            }
          } catch (e) {
            // Fallback failed
            stderr.writeln(
                'AppLogger: Failed to get application support directory: $e');
          }
        }

        if (logPath != null) {
          AppLogger.setLogPath(logPath);
          // Write debug info to stderr (will appear in console log)
          stderr.writeln('AppLogger: Set log path to: $logPath');
        } else {
          stderr.writeln(
              'AppLogger: WARNING - Could not determine log path, using default');
        }
      } catch (e, stackTrace) {
        // If setting custom path fails, use default path (will be set in initialize)
        // Cannot use AppLogger here as it's not initialized yet
        stderr.writeln('AppLogger: Error setting custom log path: $e');
        stderr.writeln('AppLogger: Stack trace: $stackTrace');
      }

      // Initialize logger first to capture all errors
      await AppLogger.initialize();

      // Log initialization success with file path for debugging
      // Use a test write to verify file logging works
      final logPath = AppLogger.getLogPath();
      if (logPath != null) {
        // Test file write immediately
        try {
          final logFile = File(logPath);
          // Write a test message directly to verify file is writable
          logFile.writeAsStringSync('=== Test Write ===\n',
              mode: FileMode.append);
          stderr.writeln('AppLogger: Test write successful to: $logPath');
          AppLogger.log('AppLogger initialized, log file: $logPath');
          AppLogger.log('AppLogger: Log file exists and is ready');
        } catch (e, stackTrace) {
          // This will be written to stderr since file logging might not work
          stderr.writeln('AppLogger: ERROR - Failed to write to log file: $e');
          stderr.writeln('AppLogger: Stack trace: $stackTrace');
          stderr.writeln('AppLogger: Log file path: $logPath');
        }
      } else {
        // Log to stderr since file logging might not be available
        stderr.writeln(
            'AppLogger: WARNING - Log file path is null after initialization');
      }
      AppLogger.log('Application starting...');

      // Clear stale LAN bootstrap service state from previous unclean exits
      await Prefs.setLanBootstrapServiceRunning(false);

      // Pass log path to C++ so V2TIMLog writes to the same file in unified format (before initSDK)
      if (logPath != null) {
        try {
          final ffiLib = Tim2ToxFfi.open();
          ffiLib.setLogFile(logPath);
        } catch (e) {
          AppLogger.warn('Could not set C++ log file: $e');
        }
      }

      // BINARY REPLACEMENT MODE: Using NativeLibraryManager instead of Platform interface
      // This allows the app to use the binary replacement solution (Dart* functions)
      // instead of the Platform interface solution (Tim2ToxSdkPlatform)
      setNativeLibraryName('tim2tox_ffi');
      AppLogger.log(
          '[main.dart] BINARY REPLACEMENT MODE: Using NativeLibraryManager with tim2tox_ffi');

      // NOTE: We do NOT set TencentCloudChatSdkPlatform.instance here
      // This allows the app to use TIMManager.instance -> NativeLibraryManager -> Dart* functions
      // Initialize window manager and tray only on desktop platforms
      if (PlatformUtils.isDesktop) {
        if (AppTray.instance.isSupported) {
          await windowManager.ensureInitialized();
          const minSize = Size(960, 600);
          await windowManager.setMinimumSize(minSize);
          const defaultSize = Size(1280, 800);
          const windowOptions = WindowOptions(
            size: defaultSize,
            minimumSize: minSize,
            title: 'toxee',
            center: true,
          );
          // Restore saved window bounds and maximized state; fallback to default on invalid
          final savedBounds = await Prefs.getWindowBounds();
          final savedMaximized = await Prefs.getWindowMaximized();
          final validBounds = savedBounds != null &&
              savedBounds.width >= minSize.width &&
              savedBounds.height >= minSize.height &&
              savedBounds.width <= 4096 &&
              savedBounds.height <= 4096;

          windowManager.addListener(_WindowStateListener());
          await windowManager.setPreventClose(true);

          // Wait until Flutter is ready before showing the window
          windowManager.waitUntilReadyToShow(windowOptions, () async {
            if (validBounds) {
              try {
                await windowManager.setBounds(savedBounds);
              } catch (_) {
                // Fallback: use default size/center
              }
            }
            await windowManager.show();
            await windowManager.focus();
            if (savedMaximized) {
              try {
                await windowManager.maximize();
              } catch (_) {}
            }
          });
          await AppTray.instance.init();
        }
      }

      // Global error capture for Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails details) {
        // Log to our logger with full stack trace
        AppLogger.logError(
          'Flutter Error: ${details.exception}',
          details.exception,
          details.stack,
        );
        // Also present error to user (shows red screen in debug mode)
        FlutterError.presentError(details);
      };

      // Capture uncaught async errors on engine side
      ui.PlatformDispatcher.instance.onError =
          (Object error, StackTrace stack) {
        AppLogger.logError('Uncaught async error', error, stack);
        return true; // Return true to prevent default error handling
      };

      // Run Prefs schema migration before any Prefs access (e.g. theme/locale)
      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      try {
        await PrefsUpgrader.run(prefs);
      } on PrefsStorageNewerThanAppException catch (e) {
        AppLogger.log(
            'Prefs stored by newer app (${e.storedVersion} > ${e.currentVersion}), showing upgrade required');
        runApp(UpgradeRequiredApp(
          storedVersion: e.storedVersion,
          currentVersion: e.currentVersion,
        ));
        return;
      }

      // Initialize theme and locale BEFORE running the app
      // This ensures the correct background color is used from the start
      AppLogger.log('Initializing theme and locale...');
      await AppTheme.initFromPrefs();
      await AppLocale.initFromPrefs();
      // Initialize UIKit theme (WeChat light/dark color scheme)
      TencentCloudChatTheme.init(
        themeModel: AppThemeConfig.createYouthfulThemeModel(),
        brightness: AppTheme.mode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      );
      AppLogger.log('Theme and locale initialized');

      AppLogger.log('Running app...');
      runApp(const EchoUIKitApp());
    },
    (Object error, StackTrace stack) {
      try {
        AppLogger.logError('Uncaught error in zone', error, stack);
      } catch (e) {
        // If logging itself fails (e.g. StackOverflow from deep Future chains),
        // fall back to stderr which doesn't allocate or call DateTime.
        try {
          stderr.writeln('[ZONE ERROR] $error');
        } catch (_) {}
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        _routePrintToLogger(line);
      },
    ),
  );
}

class EchoUIKitApp extends StatefulWidget {
  const EchoUIKitApp({super.key});
  @override
  State<EchoUIKitApp> createState() => _EchoUIKitAppState();
}

class _EchoUIKitAppState extends State<EchoUIKitApp> {
  @override
  Widget build(BuildContext context) {
    // Theme and locale are already initialized in main() before runApp()
    // So we can directly use them here without FutureBuilder
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, themeMode, _) {
        // Sync UIKit theme brightness when themeMode changes (TencentCloudChatMaterialApp
        // uses brightnessWithoutFire which does not fire the event; UIKit components
        // need the event to rebuild with new colors)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final brightness =
              themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light;
          TencentCloudChatTheme.init(brightness: brightness);
        });
        return ValueListenableBuilder<Locale>(
          valueListenable: AppLocale.locale,
          builder: (context, locale, __) {
            return TencentCloudChatMaterialApp(
              title: 'toxee',
              debugShowCheckedModeBanner: false,
              themeAnimationDuration: const Duration(milliseconds: 400),
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorSchemeSeed: AppThemeConfig.primaryColor,
                scaffoldBackgroundColor: AppThemeConfig.lightScaffoldBackground,
                textTheme: const TextTheme(
                  headlineSmall:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  titleLarge:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  titleMedium:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  titleSmall:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  bodyLarge: TextStyle(fontSize: 16),
                  bodyMedium: TextStyle(fontSize: 14),
                  bodySmall: TextStyle(fontSize: 12),
                  labelLarge:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  labelMedium:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  labelSmall:
                      TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                ),
                appBarTheme: const AppBarTheme(
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  centerTitle: false,
                ),
                cardTheme: CardThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                  ),
                  elevation: 1,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppThemeConfig.buttonBorderRadius),
                    ),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: AppThemeConfig.primaryColorDark,
                scaffoldBackgroundColor: AppThemeConfig.darkScaffoldBackground,
                textTheme: const TextTheme(
                  headlineSmall:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  titleLarge:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  titleMedium:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  titleSmall:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  bodyLarge: TextStyle(fontSize: 16),
                  bodyMedium: TextStyle(fontSize: 14),
                  bodySmall: TextStyle(fontSize: 12),
                  labelLarge:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  labelMedium:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  labelSmall:
                      TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                ),
                appBarTheme: const AppBarTheme(
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  centerTitle: false,
                ),
                cardTheme: CardThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                  ),
                  elevation: 1,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppThemeConfig.buttonBorderRadius),
                    ),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
              ),
              themeMode: themeMode,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                TencentCloudChatLocalizations.delegate, // UIKit i18n delegate
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                final backgroundColor = brightness == Brightness.dark
                    ? AppThemeConfig.darkScaffoldBackground
                    : AppThemeConfig.lightScaffoldBackground;
                return ValueListenableBuilder<bool>(
                  valueListenable: FakeUIKit.instance.callSystemReady,
                  builder: (context, ready, _) {
                    Widget content = Container(
                      color: backgroundColor,
                      child: child,
                    );
                    if (ready) {
                      final callState = FakeUIKit.instance.callStateNotifier;
                      final callManager = FakeUIKit.instance.callServiceManager;
                      if (callState != null && callManager != null) {
                        content = CallEffectsListener(
                          callState: callState,
                          manager: callManager,
                          child: CallOverlay(
                            callState: callState,
                            manager: callManager,
                            child: content,
                          ),
                        );
                      }
                    }
                    return content;
                  },
                );
              },
              home: const _StartupGate(),
            );
          },
        );
      },
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();
  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _checking = true;
  String? _error;
  bool _waitingForConnection = false;
  Timer? _timeoutTimer;
  StreamSubscription<bool>? _connectionSub;
  StartupStep _currentStep = StartupStep.checkingUserInfo;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  /// Initialize TIMManager SDK (required for binary replacement mode)
  /// This ensures _isInitSDK is set to true, allowing SDK operations to work
  Future<void> _initTIMManagerSDK() async {
    try {
      // Check if SDK is already initialized
      if (TIMManager.instance.isInitSDK()) {
        AppLogger.log('[StartupGate] TIMManager SDK already initialized');
        return;
      }

      AppLogger.log('[StartupGate] Initializing TIMManager SDK...');

      // Initialize SDK with a dummy SDKAppID (0 is used as placeholder)
      // The actual SDK initialization is done by FfiChatService.init() which calls tim2tox_ffi_init()
      // This call ensures _isInitSDK is set to true by calling DartInitSDK in the C++ layer
      final result = await TIMManager.instance.initSDK(
        sdkAppID:
            0, // Placeholder, actual initialization is done by FfiChatService
        logLevel: LogLevelEnum.V2TIM_LOG_INFO,
        uiPlatform:
            0, // Flutter FFI platform (APIType::FlutterFFI: 0x1 << 6 = 64)
      );

      if (result) {
        AppLogger.log(
            '[StartupGate] TIMManager SDK initialized successfully, _isInitSDK=${TIMManager.instance.isInitSDK()}');
      } else {
        AppLogger.log(
            '[StartupGate] TIMManager SDK initialization failed, _isInitSDK=${TIMManager.instance.isInitSDK()}');
        throw Exception('Failed to initialize TIMManager SDK');
      }
    } catch (e, stackTrace) {
      AppLogger.logError(
          '[StartupGate] Error initializing TIMManager SDK: $e', e, stackTrace);
      rethrow; // Re-throw to prevent navigation if SDK initialization fails
    }
  }

  void _updateStep(StartupStep step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  Future<void> _loadFriendsInfo(FfiChatService service) async {
    try {
      AppLogger.log('[StartupGate] Loading friends information...');

      // Trigger FakeIM to refresh conversations and contacts
      // This ensures friend list is loaded before entering HomePage
      if (FakeUIKit.instance.im != null) {
        // Refresh conversations to load friend list
        await FakeUIKit.instance.im!.refreshConversations();
        // Refresh contacts to update friend status
        await FakeUIKit.instance.im!.refreshContacts();
      }

      // Wait for friend online status to be updated
      // Poll friend list multiple times to ensure we get the latest online status
      // This is important because Tox needs time to establish connections and detect online status
      const maxAttempts =
          12; // 12 attempts * 500ms = 6 seconds max (increased from 3 seconds)
      const pollInterval = Duration(milliseconds: 500);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(pollInterval);

        // Get current friend list to check if we have online status
        final friends = await service.getFriendList();

        // Check if we have at least one friend with online status detected
        // If we have friends, check if any have online status or if we've waited enough
        bool hasOnlineStatus = false;
        if (friends.isNotEmpty) {
          // Check if any friend has online status (meaning we've detected at least one online friend)
          // OR if we've waited long enough (attempt >= 6, meaning 3 seconds)
          // This ensures we don't wait forever if all friends are offline
          hasOnlineStatus = friends.any((f) => f.online) || attempt >= 6;

          if (hasOnlineStatus || attempt >= maxAttempts - 1) {
            // We have online status or we've waited long enough
            AppLogger.log(
                '[StartupGate] Friends info loaded: ${friends.length} friends, ${friends.where((f) => f.online).length} online');
            // Refresh contacts one more time to ensure UI has latest status
            if (FakeUIKit.instance.im != null) {
              await FakeUIKit.instance.im!.refreshContacts();
            }
            break;
          }
        } else if (attempt >= 4) {
          // If no friends after 2 seconds, proceed anyway (user might not have friends)
          AppLogger.log('[StartupGate] No friends found, proceeding...');
          break;
        }
      }
    } catch (e) {
      // Log error but don't block startup
      AppLogger.logError(
          '[StartupGate] Error loading friends info: $e', e, null);
    }
  }

  Future<void> _decide() async {
    try {
      // Step 1: Check user information
      _updateStep(StartupStep.checkingUserInfo);
      final nick = await Prefs.getNickname();
      final statusMsg = await Prefs.getStatusMessage();
      final autoLogin = await Prefs.getAutoLogin();
      if (!mounted) return;

      // Check if user has registered (has nickname)
      if (nick == null || nick.trim().isEmpty) {
        setState(
            () => _checking = false); // show registration/login (LoginPage)
        return;
      }

      // Check auto-login setting
      if (!autoLogin) {
        setState(() => _checking = false); // show login page
        return;
      }

      // Step 2: Initialize service
      _updateStep(StartupStep.initializingService);

      // Ensure bootstrap node is configured before service init (for first-time startup)
      var mode = await Prefs.getBootstrapNodeMode();
      if (!PlatformUtils.isDesktop && mode == 'lan') {
        await Prefs.setBootstrapNodeMode('auto');
        mode = 'auto';
      }
      if (mode == 'auto') {
        final existingNode = await Prefs.getCurrentBootstrapNode();
        if (existingNode == null) {
          try {
            final nodes = await BootstrapNodesService.fetchNodes();
            if (nodes.isNotEmpty) {
              final onlineNode = nodes.firstWhere(
                (node) => node.status == 'ONLINE',
                orElse: () => nodes.first,
              );
              await Prefs.setCurrentBootstrapNode(
                onlineNode.ipv4,
                onlineNode.port,
                onlineNode.publicKey,
              );
              AppLogger.log(
                  '[main.dart] Auto-fetched and saved bootstrap node for first-time startup');
            }
          } catch (e) {
            AppLogger.logError(
                '[main.dart] Failed to fetch bootstrap node on first startup',
                e,
                null);
          }
        }
      }

      final account = await Prefs.getAccountByNickname(nick);
      final toxIdForStartup = account?['toxId'];

      FfiChatService service;
      if (toxIdForStartup != null && toxIdForStartup.isNotEmpty) {
        // Use AccountService for account initialization (startPolling=false so we control the flow)
        service = await AccountService.initializeServiceForAccount(
          toxId: toxIdForStartup,
          nickname: nick,
          statusMessage: statusMsg ?? '',
          startPolling: false,
        );
      } else {
        // Legacy account without toxId
        final prefs = await SharedPreferences.getInstance();
        service = FfiChatService(
          preferencesService: SharedPreferencesAdapter(prefs),
          loggerService: AppLoggerAdapter(),
          bootstrapService: BootstrapNodesAdapter(prefs),
        );
        await service.init();
        await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');
        await service.updateSelfProfile(
            nickname: nick, statusMessage: statusMsg ?? '');
      }

      // OPTIMIZATION: Start FakeUIKit early, before connection waiting
      FakeUIKit.instance.startWithFfi(service);

      // Step 3: Initialize SDK
      _updateStep(StartupStep.loggingIn);
      await _initTIMManagerSDK();
      if (mounted) _updateStep(StartupStep.initializingSDK);

      // Step 4: Start polling
      _updateStep(StartupStep.updatingProfile);
      AppLogger.log(
          '[main.dart] About to call startPolling, service type: ${service.runtimeType}');
      await service.startPolling().then((_) {
        AppLogger.log('[main.dart] startPolling completed successfully');
      }).catchError((e, stackTrace) {
        AppLogger.logError('[main.dart] startPolling failed', e, stackTrace);
      });
      AppLogger.log('[main.dart] startPolling call initiated (async)');

      // Step 6: Connect
      _updateStep(StartupStep.connecting);

      // Check if already connected
      if (service.isConnected) {
        if (!mounted) return;

        // Step 7: Load friends information
        _updateStep(StartupStep.loadingFriends);
        await _loadFriendsInfo(service);

        if (!mounted) return;
        _updateStep(StartupStep.completed);
        // Small delay to show completion state
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.of(context).pushReplacement(
          AppPageRoute(page: HomePage(service: service)),
        );
        return;
      }

      // Wait for connection with timeout
      setState(() {
        _waitingForConnection = true;
      });

      // Set 20s timeout
      _timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) {
          _connectionSub?.cancel();
          _updateStep(StartupStep.completed);
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                AppPageRoute(page: HomePage(service: service)),
              );
            }
          });
        }
      });

      // Listen for connection status
      _connectionSub =
          service.connectionStatusStream.listen((isConnected) async {
        if (isConnected && mounted && _waitingForConnection) {
          _timeoutTimer?.cancel();
          _connectionSub?.cancel();

          // Step 7: Load friends information
          _updateStep(StartupStep.loadingFriends);
          await _loadFriendsInfo(service);

          if (!mounted) return;
          _updateStep(StartupStep.completed);
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                AppPageRoute(page: HomePage(service: service)),
              );
            }
          });
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _waitingForConnection) {
      return StartupLoadingScreen(
        currentStep: _currentStep,
        errorMessage: _error,
        onRetry: _error != null ? _decide : null,
        onGoToLogin: _error != null
            ? () {
                Navigator.of(context).pushReplacement(
                  AppPageRoute(page: const LoginPage()),
                );
              }
            : null,
      );
    }
    if (_error != null) {
      return StartupLoadingScreen(
        currentStep: _currentStep,
        errorMessage: _error,
        onRetry: _decide,
        onGoToLogin: () {
          Navigator.of(context).pushReplacement(
            AppPageRoute(page: const LoginPage()),
          );
        },
      );
    }
    // Fall back to registration when no local data
    return const LoginPage();
  }
}

/// Saves window bounds and maximized state to Prefs on close (desktop).
class _WindowStateListener with WindowListener {
  @override
  void onWindowClose() async {
    try {
      final bounds = await windowManager.getBounds();
      await Prefs.setWindowBounds(bounds);
      final maximized = await windowManager.isMaximized();
      await Prefs.setWindowMaximized(maximized);
    } catch (_) {}
    await windowManager.destroy();
  }
}
