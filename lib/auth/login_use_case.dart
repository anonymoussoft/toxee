import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../runtime/tim_sdk_initializer.dart';
import '../util/account_service.dart';
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

    final account = await Prefs.getUniqueAccountByNickname(nickname);
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

      await TimSdkInitializer.ensureInitialized();

      await Prefs.setNickname(nickname);
      await Prefs.setStatusMessage(statusMessage);

      final avatarForAccount = account != null ? (account['avatarPath'] ?? '') : '';
      // Use toxIdForLogin (existing account key) so we update the list entry instead of
      // being treated as a new account; service.selfId may differ in format (e.g. 76 vs 64 chars).
      await Prefs.addAccount(
        toxId: toxIdForLogin,
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
    await TimSdkInitializer.ensureInitialized();

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
}
