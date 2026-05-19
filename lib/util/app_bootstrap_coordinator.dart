import 'dart:async';
import 'dart:io';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'app_paths.dart';
import 'logger.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';

/// Orchestrates runtime assembly and service startup: SessionRuntimeCoordinator,
/// TIMManager SDK, and polling. Used from the startup gate so UI code does not assemble these.
class AppBootstrapCoordinator {
  AppBootstrapCoordinator._();

  /// Initialize session runtime (FakeUIKit, platform, CallServiceManager), TIM SDK, and start polling.
  /// Throws on failure so the caller can show error/retry UI.
  static Future<void> boot(FfiChatService service) async {
    await SessionRuntimeCoordinator(service: service).ensureInitialized();
    await TimSdkInitializer.ensureInitialized();

    AppLogger.log('[AppBootstrapCoordinator] Starting polling...');
    await service.startPolling();
    AppLogger.log('[AppBootstrapCoordinator] Polling started');

    // iOS: now that the account is logged in and toxId is known, mark the
    // regenerable / private-key directories excluded from iCloud / iTunes
    // backup (H8 part 1, 2026-05-19 persistence review).
    //   - file_recv: derivable received-file scratch space; should not bloat
    //     backups.
    //   - tim2tox/: holds the tox profile (private key). Excluded so it
    //     never leaves the device through iCloud. The chat history directory
    //     is intentionally NOT excluded — that's the user's irreplaceable
    //     data and must remain restorable.
    if (Platform.isIOS) {
      final toxId = service.selfId;
      if (toxId.isNotEmpty) {
        unawaited(_markIosPostLoginExclusions(toxId));
      }
    }
  }

  static Future<void> _markIosPostLoginExclusions(String toxId) async {
    try {
      final fileRecv = await AppPaths.getAccountFileRecvPath(toxId);
      await AppPaths.markExcludedFromBackup(fileRecv);
      final profileDir = (await AppPaths.toxProfileDir).path;
      await AppPaths.markExcludedFromBackup(profileDir);
    } catch (e, st) {
      AppLogger.logError(
          '[AppBootstrapCoordinator] iOS backup-exclusion marking failed '
          '(non-fatal)',
          e,
          st);
    }
  }
}
