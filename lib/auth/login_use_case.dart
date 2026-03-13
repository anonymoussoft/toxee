import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../util/account_service.dart';
import '../util/logger.dart';
import '../util/prefs.dart';

/// Input parameters for [LoginUseCase.execute].
class LoginParams {
  const LoginParams({
    required this.nickname,
    required this.statusMessage,
    this.password,
  });

  final String nickname;
  final String statusMessage;
  final String? password;
}

/// Result of a successful login.
class LoginSuccess {
  const LoginSuccess({required this.service});

  final FfiChatService service;
}

/// Encapsulates login business logic: account resolution, service initialization,
/// TIMManager SDK init, and prefs persistence. UI only validates form and navigates.
class LoginUseCase {
  LoginUseCase();

  /// Performs login. Returns [LoginSuccess] or throws.
  /// Caller is responsible for password prompt when account has password.
  Future<LoginSuccess> execute(LoginParams params) async {
    final nickname = params.nickname.trim();
    final statusMessage = params.statusMessage.trim();

    if (nickname.isEmpty) {
      throw Exception('Nickname cannot be empty');
    }

    final account = await Prefs.getAccountByNickname(nickname);
    if (account == null) {
      final savedNickname = await Prefs.getNickname();
      if (savedNickname == null || savedNickname.trim().isEmpty) {
        throw Exception('User not found; please register');
      }
      if (savedNickname.trim() != nickname) {
        throw Exception('Nickname does not match');
      }
    }

    final toxIdForLogin = account?['toxId'];
    if (toxIdForLogin != null && toxIdForLogin.isNotEmpty) {
      final hasPassword = await Prefs.hasAccountPassword(toxIdForLogin);
      if (hasPassword) {
        final password = params.password ?? '';
        if (password.isEmpty) {
          throw Exception('Password required');
        }
        final ok = await Prefs.verifyAccountPassword(toxIdForLogin, password);
        if (!ok) {
          throw Exception('Invalid password');
        }
      }

      final service = await AccountService.initializeServiceForAccount(
        toxId: toxIdForLogin,
        nickname: nickname,
        statusMessage: statusMessage,
        password: params.password,
      );

      await _initTIMManagerSDK();

      await Prefs.setNickname(nickname);
      await Prefs.setStatusMessage(statusMessage);

      final avatarForAccount = account != null ? (account['avatarPath'] ?? '') : '';
      await Prefs.addAccount(
        toxId: service.selfId,
        nickname: nickname,
        statusMessage: statusMessage,
        avatarPath: avatarForAccount.isNotEmpty ? avatarForAccount : null,
      );

      return LoginSuccess(service: service);
    }

    // Legacy account without toxId
    final prefs = await SharedPreferences.getInstance();
    final service = FfiChatService(
      preferencesService: SharedPreferencesAdapter(prefs),
      loggerService: AppLoggerAdapter(),
      bootstrapService: BootstrapNodesAdapter(prefs),
    );
    await service.init();
    await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');
    await _initTIMManagerSDK();

    final toxId = service.selfId;
    await Prefs.setNickname(nickname);
    await Prefs.setStatusMessage(statusMessage);
    await Prefs.setCurrentAccountToxId(toxId);
    await Prefs.addAccount(
      toxId: toxId,
      nickname: nickname,
      statusMessage: statusMessage,
    );
    await service.updateSelfProfile(nickname: nickname, statusMessage: statusMessage);
    await service.startPolling();

    return LoginSuccess(service: service);
  }

  static Future<void> _initTIMManagerSDK() async {
    try {
      if (TIMManager.instance.isInitSDK()) {
        AppLogger.log('[LoginUseCase] TIMManager SDK already initialized');
        return;
      }
      AppLogger.log('[LoginUseCase] Initializing TIMManager SDK...');
      final result = await TIMManager.instance.initSDK(
        sdkAppID: 0,
        logLevel: LogLevelEnum.V2TIM_LOG_INFO,
        uiPlatform: 0,
      );
      if (result) {
        AppLogger.log(
          '[LoginUseCase] TIMManager SDK initialized, _isInitSDK=${TIMManager.instance.isInitSDK()}',
        );
      } else {
        throw Exception('Failed to initialize TIMManager SDK');
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[LoginUseCase] TIMManager SDK init error: $e', e, stackTrace);
      rethrow;
    }
  }
}
