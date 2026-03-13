import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../auth/login_use_case.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Result of [LoginPageController.login].
sealed class LoginControllerResult {
  const LoginControllerResult();
}

final class LoginControllerSuccess extends LoginControllerResult {
  const LoginControllerSuccess(this.service);
  final FfiChatService service;
}

final class LoginControllerFailure extends LoginControllerResult {
  const LoginControllerFailure(this.message);
  final String message;
}

/// Result of [LoginPageController.importAccount].
sealed class ImportResult {
  const ImportResult();
}

final class ImportSuccess extends ImportResult {
  const ImportSuccess();
}

final class ImportFailure extends ImportResult {
  const ImportFailure(this.message);
  final String message;
}

/// Orchestrates login and import flows for [LoginPage].
/// Keeps UI to form binding, dialogs, and navigation.
class LoginPageController {
  LoginPageController({LoginUseCase? loginUseCase})
      : _loginUseCase = loginUseCase ?? LoginUseCase();

  final LoginUseCase _loginUseCase;

  /// Runs login with the given credentials. Password must be provided when account has one.
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    try {
      final success = await _loginUseCase.execute(LoginParams(
        nickname: nickname,
        statusMessage: statusMessage,
        password: password,
      ));
      return LoginControllerSuccess(success.service);
    } catch (e, st) {
      AppLogger.logError('[LoginPageController] Login failed', e, st);
      final message =
          e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
      return LoginControllerFailure(message);
    }
  }

  /// Imports an account from a .tox or .zip file. Uses [requestPassword] when file is encrypted.
  Future<ImportResult> importAccount({
    required Future<String?> Function(String prompt) requestPassword,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tox', 'zip'],
      );
      if (result == null || result.files.single.path == null) {
        return const ImportFailure('No file selected');
      }
      final filePath = result.files.single.path!;
      final isZip = filePath.toLowerCase().endsWith('.zip');

      String? password;
      Map<String, dynamic> accountData;

      if (isZip) {
        final metadata = await AccountExportService.readFullBackupMetadata(filePath);
        final toxId = metadata['toxId']!;
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null) {
          return const ImportFailure('Account already exists');
        }
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profileFilePath).exists()) {
          return const ImportFailure('Account already exists');
        }
        try {
          accountData = await AccountExportService.importFullBackup(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            password = await requestPassword('Enter password to import');
            if (password == null) return const ImportFailure('Cancelled');
            accountData = await AccountExportService.importFullBackup(
              filePath: filePath,
              password: password,
            );
          } else {
            rethrow;
          }
        }
      } else {
        try {
          accountData = await AccountExportService.importAccountData(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            password = await requestPassword('Enter password to import');
            if (password == null) return const ImportFailure('Cancelled');
            accountData = await AccountExportService.importAccountData(
              filePath: filePath,
              password: password,
            );
          } else {
            rethrow;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';

      if (!isZip) {
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null) {
          return const ImportFailure('Account already exists');
        }
      }

      if (!isZip && toxProfile != null) {
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profileFilePath).exists()) {
          return const ImportFailure('Account already exists');
        }
        await Directory(profileDir).create(recursive: true);
        await File(profileFilePath).writeAsBytes(toxProfile);
      }

      final displayNickname =
          importedNickname.isNotEmpty ? importedNickname : 'Imported account';
      await Prefs.addAccount(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (password != null && password.isNotEmpty) {
        await Prefs.setAccountPassword(toxId, password);
      }
      return const ImportSuccess();
    } catch (e, st) {
      AppLogger.logError('[LoginPageController] Import failed', e, st);
      return ImportFailure('Failed to import: ${e.toString()}');
    }
  }
}
