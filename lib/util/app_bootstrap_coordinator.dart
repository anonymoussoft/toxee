import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'logger.dart';
import '../sdk_fake/fake_uikit_core.dart';

/// Orchestrates runtime assembly and service startup: FakeUIKit, TIMManager SDK,
/// and polling. Used from the startup gate so UI code does not assemble these.
class AppBootstrapCoordinator {
  AppBootstrapCoordinator._();

  /// Start FakeUIKit with [service], initialize TIMManager SDK, and start polling.
  /// Throws on failure so the caller can show error/retry UI.
  static Future<void> boot(FfiChatService service) async {
    FakeUIKit.instance.startWithFfi(service);

    if (!TIMManager.instance.isInitSDK()) {
      AppLogger.log('[AppBootstrapCoordinator] Initializing TIMManager SDK...');
      final result = await TIMManager.instance.initSDK(
        sdkAppID: 0,
        logLevel: LogLevelEnum.V2TIM_LOG_INFO,
        uiPlatform: 0,
      );
      if (!result) {
        throw Exception('Failed to initialize TIMManager SDK');
      }
      AppLogger.log('[AppBootstrapCoordinator] TIMManager SDK initialized');
    }

    AppLogger.log('[AppBootstrapCoordinator] Starting polling...');
    await service.startPolling();
    AppLogger.log('[AppBootstrapCoordinator] Polling started');
  }
}
