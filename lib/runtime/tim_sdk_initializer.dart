import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';

/// Single place for TIMManager SDK initialization. Idempotent.
class TimSdkInitializer {
  TimSdkInitializer._();

  static Future<void> ensureInitialized() async {
    if (TIMManager.instance.isInitSDK()) return;

    final ok = await TIMManager.instance.initSDK(
      sdkAppID: 0,
      logLevel: LogLevelEnum.V2TIM_LOG_INFO,
      uiPlatform: 0,
    );
    if (!ok) {
      throw Exception('Failed to initialize TIMManager SDK');
    }
  }
}
