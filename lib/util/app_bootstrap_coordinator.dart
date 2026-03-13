import 'package:tim2tox_dart/service/ffi_chat_service.dart';

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
  }
}
