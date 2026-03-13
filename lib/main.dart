import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'ui/widgets/app_page_route.dart';
import 'package:tencent_cloud_chat_common/widgets/material_app.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'ui/login_page.dart';
import 'ui/home_page.dart';
import 'ui/startup_loading_screen.dart';
import 'ui/upgrade_required_screen.dart';
import 'sdk_fake/fake_uikit_core.dart';
import 'util/prefs.dart';
import 'util/theme_controller.dart';
import 'util/locale_controller.dart';
import 'i18n/app_localizations.dart';
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
import 'util/app_bootstrap_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';

import 'bootstrap/app_bootstrap.dart';
import 'bootstrap/app_bootstrap_result.dart';

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

      final result = await AppBootstrap.initialize();

      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.logError(
          'Flutter Error: ${details.exception}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };

      ui.PlatformDispatcher.instance.onError =
          (Object error, StackTrace stack) {
        AppLogger.logError('Uncaught async error', error, stack);
        return true;
      };

      switch (result) {
        case AppBootstrapSuccess():
          AppLogger.log('Running app...');
          runApp(const EchoUIKitApp());
        case AppBootstrapUpgradeRequired(:final storedVersion, :final currentVersion):
          runApp(UpgradeRequiredApp(
            storedVersion: storedVersion,
            currentVersion: currentVersion,
          ));
      }
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
  void initState() {
    super.initState();
    AppTheme.mode.addListener(_syncUIKitThemeBrightness);
    _syncUIKitThemeBrightness();
  }

  void _syncUIKitThemeBrightness() {
    final mode = AppTheme.mode.value;
    final brightness =
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
    TencentCloudChatTheme.init(brightness: brightness);
  }

  @override
  void dispose() {
    AppTheme.mode.removeListener(_syncUIKitThemeBrightness);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme and locale are already initialized in main() before runApp()
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: AppLocale.locale,
          builder: (context, locale, __) {
            return TencentCloudChatMaterialApp(
              title: 'Toxee',
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

      // Step 3–5: Bootstrap runtime (FakeUIKit, SDK, polling) via coordinator
      _updateStep(StartupStep.loggingIn);
      await AppBootstrapCoordinator.boot(service);
      if (!mounted) return;

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

