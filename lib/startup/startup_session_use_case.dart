import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../util/account_service.dart';
import '../util/app_bootstrap_coordinator.dart';
import '../util/bootstrap_nodes.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';

import 'startup_outcome.dart';
import 'startup_step.dart';

/// Encapsulates startup policy: user check, service init, bootstrap, connection.
/// Ownership and cleanup of [FfiChatService] are handled here; the widget only
/// reacts to [StartupOutcome] and (for [StartupWaitForConnection]) sets up
/// timeout and connection listener.
class StartupSessionUseCase {
  /// Runs the startup flow. Reports steps via [onStepChanged].
  /// When already connected, calls [loadFriends] then returns [StartupOpenHome].
  /// When not connected, returns [StartupWaitForConnection]; the widget must
  /// wait for connection, call [loadFriends], then navigate.
  Future<StartupOutcome> execute({
    required void Function(StartupStep) onStepChanged,
    required Future<void> Function(FfiChatService) loadFriends,
  }) async {
    FfiChatService? service;
    try {
      onStepChanged(StartupStep.checkingUserInfo);
      final nick = await Prefs.getNickname();
      final statusMsg = await Prefs.getStatusMessage();
      final autoLogin = await Prefs.getAutoLogin();

      if (nick == null || nick.trim().isEmpty) {
        return const StartupShowLogin();
      }
      if (!autoLogin) {
        return const StartupShowLogin();
      }

      onStepChanged(StartupStep.initializingService);

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
                  '[StartupSessionUseCase] Auto-fetched and saved bootstrap node');
            }
          } catch (e) {
            AppLogger.logError(
                '[StartupSessionUseCase] Failed to fetch bootstrap node', e, null);
          }
        }
      }

      Map<String, String>? account;
      try {
        account = await Prefs.getUniqueAccountByNickname(nick);
      } on StateError {
        return const StartupShowLogin();
      }
      final toxIdForStartup = account?['toxId'];

      if (toxIdForStartup != null && toxIdForStartup.isNotEmpty) {
        service = await AccountService.initializeServiceForAccount(
          toxId: toxIdForStartup,
          nickname: nick,
          statusMessage: statusMsg ?? '',
          startPolling: false,
        );
      } else {
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

      final currentService = service;

      onStepChanged(StartupStep.loggingIn);
      await AppBootstrapCoordinator.boot(currentService);

      onStepChanged(StartupStep.connecting);

      if (currentService.isConnected) {
        onStepChanged(StartupStep.loadingFriends);
        await loadFriends(currentService);
        onStepChanged(StartupStep.completed);
        return StartupOpenHome(currentService);
      }

      return StartupWaitForConnection(currentService);
    } catch (e) {
      if (service != null) {
        try {
          await AccountService.teardownCurrentSession(
            service: service,
            reEncryptProfile: true,
          );
        } catch (cleanupError, cleanupSt) {
          AppLogger.logError(
            '[StartupSessionUseCase] cleanup after startup failure',
            cleanupError,
            cleanupSt,
          );
        }
      }
      return StartupShowError(e.toString());
    }
  }
}
