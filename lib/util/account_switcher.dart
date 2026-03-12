import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'prefs.dart';
import 'tox_utils.dart';
import 'account_service.dart';
import '../ui/home_page.dart';
import '../ui/login_page.dart';
import '../i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Account switcher service for switching between multiple accounts
class AccountSwitcher {
  /// Switch to a different account
  ///
  /// This will:
  /// 1. Teardown current session (dispose SDK, re-encrypt profile)
  /// 2. Initialize service for target account
  /// 3. Update account's lastLoginTime
  /// 4. Navigate to HomePage
  static Future<void> switchAccount({
    required BuildContext context,
    required String targetToxId,
    FfiChatService? currentService,
  }) async {
    try {
      // Get target account info
      final targetAccount = await Prefs.getAccountByToxId(targetToxId);
      if (targetAccount == null) {
        throw Exception('Target account not found');
      }

      // 1. Teardown current session (re-encrypts profile if needed)
      await AccountService.teardownCurrentSession(service: currentService);

      // 2. Update target account's lastLoginTime
      await Prefs.addAccount(
        toxId: targetToxId,
        nickname: targetAccount['nickname'],
        statusMessage: targetAccount['statusMessage'],
      );

      // 3. Check if target account has a password
      String? password;
      final hasPassword = await Prefs.hasAccountPassword(targetToxId);
      if (hasPassword && context.mounted) {
        password = await _showPasswordDialog(context, targetAccount['nickname'] ?? '');
        if (password == null) {
          // User cancelled – navigate to login page
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
          }
          return;
        }
        final isValid = await Prefs.verifyAccountPassword(targetToxId, password);
        if (!isValid) {
          throw Exception('Invalid password');
        }
      }

      // 4. Initialize service for target account
      final newService = await AccountService.initializeServiceForAccount(
        toxId: targetToxId,
        nickname: targetAccount['nickname'],
        statusMessage: targetAccount['statusMessage'],
        password: password,
      );

      // 5. Verify toxId
      final actualToxId = newService.selfId;
      if (!compareToxIds(actualToxId, targetToxId)) {
        // Log warning but continue
      }

      // 6. Navigate to HomePage
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomePage(service: newService)),
          (route) => false,
        );
      }
    } catch (e) {
      // Show error and navigate back to login page
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToSwitchAccount(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
      rethrow;
    }
  }

  static Future<String?> _showPasswordDialog(BuildContext context, String nickname) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.enterPasswordForAccount(nickname)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.password,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }
}
