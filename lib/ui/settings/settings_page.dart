import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../util/app_paths.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';


import 'dart:async';
import 'dart:math';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/locale_controller.dart';
import '../../util/prefs.dart';
import '../widgets/section_header.dart';
import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/account_switcher.dart';

import '../../util/account_service.dart';
import '../../util/tox_utils.dart';
import '../../util/logger.dart';
import '../../util/responsive_layout.dart';
import '../login_page.dart';
import 'bootstrap_settings_section.dart';
import 'global_settings_section.dart';

/// English words shown for confirmation when deleting account without password.
const _kDeleteConfirmWords = <String>[
  'delete', 'confirm', 'remove', 'account', 'permanent', 'cancel', 'proceed',
  'warning', 'caution', 'irreversible', 'data', 'erase', 'type', 'word',
  'verify', 'submit', 'final', 'accept', 'continue',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.service,
    required this.connectionStatusStream,
    required this.autoAcceptFriends,
    required this.onAutoAcceptFriendsChanged,
    required this.autoAcceptGroupInvites,
    required this.onAutoAcceptGroupInvitesChanged,
  });
  final FfiChatService service;
  final Stream<bool> connectionStatusStream; // Kept for API compatibility but not used
  final bool autoAcceptFriends;
  final ValueChanged<bool> onAutoAcceptFriendsChanged;
  final bool autoAcceptGroupInvites;
  final ValueChanged<bool> onAutoAcceptGroupInvitesChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoLogin = true; // Auto-login setting
  String? _currentNickname; // Current user nickname
  String? _avatarPath; // Current user avatar path
  StreamSubscription<String>? _avatarUpdatedSubscription;
  
  // Account management
  List<Map<String, String>> _accountList = [];
  bool _accountListExpanded = false;
  static const int _accountListPreviewCount = 3;
  Timer? _lastLoginTimeUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadAutoLogin();
    _loadCurrentNickname();
    _loadAvatarPath();
    _loadAccountList();
    _startLastLoginTimeUpdateTimer();
    _avatarUpdatedSubscription =
        widget.service.avatarUpdated.listen((updatedUserId) {
      final selfId = widget.service.selfId;
      if (selfId.isEmpty) return;
      final normalizedSelf =
          selfId.length > 64 ? selfId.substring(0, 64) : selfId;
      final normalizedUpdated = updatedUserId.length > 64
          ? updatedUserId.substring(0, 64)
          : updatedUserId;
      if (updatedUserId == selfId ||
          updatedUserId == normalizedSelf ||
          normalizedUpdated == normalizedSelf) {
        if (_avatarPath != null && _avatarPath!.isNotEmpty) {
          FileImage(File(_avatarPath!)).evict();
        }
        _loadAvatarPath();
      }
    });
  }

  @override
  void dispose() {
    _avatarUpdatedSubscription?.cancel();
    _lastLoginTimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAvatarPath() async {
    final avatar = await Prefs.getAvatarPath();
    if (mounted) {
      setState(() {
        _avatarPath = avatar;
      });
    }
  }

  Future<void> _loadAutoLogin() async {
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      final enabled = await Prefs.getAutoLogin(toxId);
      if (mounted) {
        setState(() {
          _autoLogin = enabled;
        });
      }
    }
  }

  Future<void> _setAutoLogin(bool value) async {
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoLogin(value, toxId);
      if (mounted) {
        setState(() {
          _autoLogin = value;
        });
      }
    }
  }

  Future<void> _loadCurrentNickname() async {
    final nick = await Prefs.getNickname();
    if (mounted) {
      setState(() {
        _currentNickname = nick;
      });
    }
  }

  Future<void> _loadAccountList() async {
    final accounts = await Prefs.getAccountList();
    if (mounted) {
      setState(() {
        _accountList = List<Map<String, String>>.from(accounts)
          ..sort((a, b) {
            final aIsCurrent = compareToxIds(a['toxId'] ?? '', widget.service.selfId);
            final bIsCurrent = compareToxIds(b['toxId'] ?? '', widget.service.selfId);
            if (aIsCurrent) return -1;
            if (bIsCurrent) return 1;
            return 0;
          });
      });
    }
  }

  void _startLastLoginTimeUpdateTimer() {
    // Update current account's lastLoginTime every 5 minutes
    _lastLoginTimeUpdateTimer?.cancel();
    _lastLoginTimeUpdateTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      final toxId = widget.service.selfId;
      if (toxId.isNotEmpty && mounted) {
        final account = await Prefs.getAccountByToxId(toxId);
        if (account != null) {
          await Prefs.addAccount(
            toxId: toxId,
            nickname: account['nickname'],
            statusMessage: account['statusMessage'],
          );
          await _loadAccountList();
        }
      }
    });
  }

  String _formatLastLoginTime(String? isoString, BuildContext context) {
    if (isoString == null || isoString.isEmpty) return AppLocalizations.of(context)!.never;
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 0) {
        return AppLocalizations.of(context)!.daysAgo(difference.inDays, difference.inDays > 1 ? 's' : '');
      } else if (difference.inHours > 0) {
        return AppLocalizations.of(context)!.hoursAgo(difference.inHours, difference.inHours > 1 ? 's' : '');
      } else if (difference.inMinutes > 0) {
        return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes, difference.inMinutes > 1 ? 's' : '');
      } else {
        return AppLocalizations.of(context)!.justNow;
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  String _getToxIdPrefix(String toxId) {
    return toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
  }

  Future<void> _switchAccount(Map<String, String> account) async {
    final toxId = account['toxId'];
    if (toxId == null || toxId.isEmpty) return;

    final currentToxId = widget.service.selfId;
    if (compareToxIds(toxId, currentToxId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.thisAccountIsAlreadyLoggedIn)),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.switchAccount),
        content: Text(AppLocalizations.of(context)!.switchAccountConfirm(account['nickname'] ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.switchAccount),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await AccountSwitcher.switchAccount(
          context: context,
          targetToxId: toxId,
          currentService: widget.service,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.failedToSwitchAccount(e.toString())),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  /// Show export format chooser, then export.
  Future<void> _showExportOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppLocalizations.of(context)!.exportAccount,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Profile (.tox)'),
              subtitle: const Text('qTox compatible, profile only'),
              onTap: () => Navigator.of(ctx).pop('tox'),
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: const Text('Full Backup (.zip)'),
              subtitle: const Text('Profile + chat history + settings'),
              onTap: () => Navigator.of(ctx).pop('zip'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'tox') {
      await _exportAccount();
    } else if (choice == 'zip') {
      await _exportFullBackup();
    }
  }

  /// Export a full .zip backup including profile, chat history, and metadata.
  Future<void> _exportFullBackup() async {
    final toxId = widget.service.selfId;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountToExport),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final account = await Prefs.getAccountByToxId(toxId);
        final nickname = account?['nickname'] ?? 'account';
        final toxIdPrefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
        final safeNickname = nickname.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final defaultFileName = '${safeNickname}_${toxIdPrefix}_backup.zip';

        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.of(context)!.exportAccount,
          fileName: defaultFileName,
        );
      }

      if (outputPath == null) return;

      final filePath = await AccountExportService.exportFullBackup(
        toxId: toxId,
        filePath: outputPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.accountExportedSuccessfully(filePath)),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Full backup export error', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToExportAccount(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _exportAccount() async {
    final toxId = widget.service.selfId;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountToExport),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Check if account has password
    final hasPassword = await Prefs.hasAccountPassword(toxId);
    String? password;
    
    if (hasPassword) {
      password = await _showConfirmPasswordDialog(AppLocalizations.of(context)!.enterPasswordToExport);
      if (password == null) return;

      final isValid = await Prefs.verifyAccountPassword(toxId, password);
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidPassword),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    try {
      // Show file picker to select save location
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Generate default filename
        final account = await Prefs.getAccountByToxId(toxId);
        final nickname = account?['nickname'] ?? 'account';
        final toxIdPrefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
        final safeNickname = nickname.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final defaultFileName = '${safeNickname}_$toxIdPrefix.tox';
        
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.of(context)!.exportAccount,
          fileName: defaultFileName,
        );
      }

      if (outputPath == null) return;

      final filePath = await AccountExportService.exportAccountData(
        toxId: toxId,
        password: password,
        filePath: outputPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.accountExportedSuccessfully(filePath)),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      AppLogger.logError('Export account error', e, stackTrace);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToExportAccount(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _importAccount() async {
    try {
      // Show file picker for .tox and .zip files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tox', 'zip'],
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      final isZip = filePath.toLowerCase().endsWith('.zip');

      // Check if file is encrypted by reading first bytes and checking magic number
      String? password;
      try {
        final file = File(filePath);
        final fileData = await file.readAsBytes();
        if (fileData.length >= 80) {
          // Import will check encryption, but we need to prompt for password first if encrypted
          // For now, we'll let importAccountData/importFullBackup handle the encryption check
          // If it throws an error about password, we'll catch and prompt
        }
      } catch (e) {
        // Error reading file, continue with import (will handle error there)
      }

      // Import account data (will check encryption and prompt for password if needed)
      Map<String, dynamic> accountData;
      try {
        if (isZip) {
          accountData = await AccountExportService.importFullBackup(
            filePath: filePath,
            password: password,
          );
        } else {
          accountData = await AccountExportService.importAccountData(
            filePath: filePath,
            password: password,
          );
        }
      } catch (e) {
        // If error mentions password, prompt for it
        if (e.toString().contains('Password required') || e.toString().contains('password')) {
          if (mounted) {
            password = await _showConfirmPasswordDialog(
              AppLocalizations.of(context)!.enterPasswordToImport
            );
            if (password == null) return;
            
            // Retry with password
            if (isZip) {
              accountData = await AccountExportService.importFullBackup(
                filePath: filePath,
                password: password,
              );
            } else {
              accountData = await AccountExportService.importAccountData(
                filePath: filePath,
                password: password,
              );
            }
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      final toxId = accountData['toxId'] as String;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';

      final existingAccount = await Prefs.getAccountByToxId(toxId);
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      // Target path for tox_profile.tox: profiles/p_<toxIdFirst16>/tox_profile.tox
      final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
      if (existingAccount != null || await File(profileFilePath).exists()) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.importAccount),
              content: Text(AppLocalizations.of(context)!.accountAlreadyExists),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context)!.ok),
                ),
              ],
            ),
          );
        }
        return;
      }

      // For .tox imports, write profile; .zip imports already wrote it in importFullBackup
      if (!isZip && toxProfile != null) {
        final parentDir = Directory(profileDir);
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        final toxProfileFile = File(profileFilePath);
        await toxProfileFile.writeAsBytes(toxProfile);
      }

      // Add/update account (.zip may contain nickname, .tox does not)
      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : AppLocalizations.of(context)!.importedAccount;
      await Prefs.addAccount(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '', // .tox files don't contain status message
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );

      // If password was used for import, set it for the account
      if (password != null && password.isNotEmpty) {
        await Prefs.setAccountPassword(toxId, password);
      }

      // Reload account list
      await _loadAccountList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.accountImportedSuccessfully),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[SettingsPage] Import account failed: $e', e, stackTrace);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.importAccount),
            content: Text(AppLocalizations.of(context)!.failedToImportAccount(e.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.of(context)!.ok),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _setAccountPassword() async {
    final toxId = widget.service.selfId;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountSelected),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final hasPassword = await Prefs.hasAccountPassword(toxId);
    
    // Show password input dialog
    final password = await _showSetPasswordDialog(hasPassword);
    if (password == null) return;

    try {
      if (password.isEmpty) {
        // Remove password
        await Prefs.removeAccountPassword(toxId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.passwordRemoved),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } else {
        // Set password
        await Prefs.setAccountPassword(toxId, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.passwordSetSuccessfully),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToSetPassword(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Password + confirm password dialog for export/import; returns password if both match.
  Future<String?> _showConfirmPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                hintText: AppLocalizations.of(context)!.ircChannelPasswordHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.confirmPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final pwd = passwordController.text;
              if (pwd != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.passwordsDoNotMatch),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(pwd);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSetPasswordDialog(bool hasPassword) async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasPassword ? AppLocalizations.of(context)!.changePassword : AppLocalizations.of(context)!.setPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.newPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                ),
                hintText: AppLocalizations.of(context)!.leaveEmptyToRemovePassword,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.confirmPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final password = passwordController.text;
              final confirm = confirmPasswordController.text;
              
              if (password != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.passwordsDoNotMatch),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
                return;
              }
              
              Navigator.of(context).pop(password);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.logOut),
        content: Text(AppLocalizations.of(context)!.logOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppLocalizations.of(context)!.logOut),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AccountService.teardownCurrentSession(service: widget.service);
      await Prefs.setCurrentAccountToxId(null);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sync UIKit locale with app locale after this frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        TencentCloudChatIntl().setLocale(AppLocale.locale.value);
      } catch (_) {}
    });
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocale.locale,
      builder: (context, locale, _) {
        final tL10n = TencentCloudChatLocalizations.of(context);
        if (tL10n == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => SafeArea(
            child: ListView(
            padding: ResponsiveLayout.responsivePadding(context),
            children: [
          // Account Info Section
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: AppLocalizations.of(context)!.accountInfo),
                  const SizedBox(height: 8),
                  if (_currentNickname != null) ...[
                    Row(
                      children: [
                        // User avatar
                        CircleAvatar(
                          key: ValueKey('settings-avatar-$_avatarPath'),
                          radius: 20,
                          backgroundColor: colorTheme.primaryColor,
                          child: _avatarPath != null && _avatarPath!.isNotEmpty && File(_avatarPath!).existsSync()
                              ? ClipOval(
                                  child: Image.file(
                                    File(_avatarPath!),
                                    key: ValueKey('settings-avatar-img-$_avatarPath'),
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Text(
                                  (_currentNickname!.isNotEmpty ? _currentNickname![0] : 'U').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: colorTheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _currentNickname!,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: Text(AppLocalizations.of(context)!.exportAccount),
                          onPressed: _showExportOptions,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.lock, size: 18),
                          label: Text(AppLocalizations.of(context)!.setPassword),
                          onPressed: _setAccountPassword,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(AppLocalizations.of(context)!.logOut),
                          onPressed: _logout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppThemeConfig.errorColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                        border: Border.all(color: AppThemeConfig.errorColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppThemeConfig.errorColor, size: 20),
                              AppSpacing.horizontalSm,
                              Text(
                                AppLocalizations.of(context)!.deleteAccount,
                                style: const TextStyle(
                                  color: AppThemeConfig.errorColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          AppSpacing.verticalMd,
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: Text(AppLocalizations.of(context)!.deleteAccount),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppThemeConfig.errorColor,
                              side: const BorderSide(color: AppThemeConfig.errorColor),
                            ),
                            onPressed: () => _showDeleteAccountConfirmation(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Auto Login Section
                    _HoverableSettingsRow(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.autoLogin,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context)!.autoLoginDesc,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorTheme.secondaryTextColor,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _autoLogin,
                            onChanged: (value) => _setAutoLogin(value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Auto Accept Friends Section
                    _HoverableSettingsRow(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.autoAcceptFriendRequests,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context)!.autoAcceptFriendRequestsDesc,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorTheme.secondaryTextColor,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: widget.autoAcceptFriends,
                            onChanged: widget.onAutoAcceptFriendsChanged,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Auto Accept Group Invites Section
                    _HoverableSettingsRow(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.autoAcceptGroupInvites,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context)!.autoAcceptGroupInvitesDesc,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorTheme.secondaryTextColor,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: widget.autoAcceptGroupInvites,
                            onChanged: widget.onAutoAcceptGroupInvitesChanged,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Account Management Section (inside Account Info)
                    SectionHeader(title: AppLocalizations.of(context)!.accountManagement),
                    const SizedBox(height: 8),
                    // Account List (default show 3, expand to show all)
                    if (_accountList.isNotEmpty) ...[
                      Text(
                        AppLocalizations.of(context)!.localAccounts,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _accountListExpanded
                            ? _accountList.length
                            : (_accountList.length > _accountListPreviewCount
                                ? _accountListPreviewCount
                                : _accountList.length),
                        itemBuilder: (context, index) {
                            final account = _accountList[index];
                            final accountToxId = account['toxId'] ?? '';
                            final lastLogin = account['lastLoginTime'];
                            // Use compareToxIds so 64-char (public key) and 76-char (address) from GetLoginUser match
                            final isCurrentAccount = compareToxIds(accountToxId, widget.service.selfId);

                            return _AccountCardItem(
                              account: account,
                              isCurrentAccount: isCurrentAccount,
                              colorTheme: colorTheme,
                              onSwitch: () => _switchAccount(account),
                              currentChip: Chip(
                                label: Text(AppLocalizations.of(context)!.current),
                                backgroundColor: colorTheme.primaryColor,
                                labelStyle: TextStyle(color: colorTheme.onPrimary),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${AppLocalizations.of(context)!.userId}: ${_getToxIdPrefix(accountToxId)}...'),
                                  Text(
                                    '${AppLocalizations.of(context)!.lastLogin}: ${_formatLastLoginTime(lastLogin, context)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (_accountList.length > _accountListPreviewCount) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => setState(() => _accountListExpanded = !_accountListExpanded),
                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _accountListExpanded ? Icons.expand_less : Icons.expand_more,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _accountListExpanded
                                      ? AppLocalizations.of(context)!.showLess
                                      : AppLocalizations.of(context)!.showMore(_accountList.length - _accountListPreviewCount),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    // Action Buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(AppLocalizations.of(context)!.importAccount),
                          onPressed: _importAccount,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Global settings (appearance, language, notification, downloads, auto-download)
          GlobalSettingsSection(
            colorTheme: colorTheme,
            toxId: widget.service.selfId,
          ),
          const SizedBox(height: 12),
          // Bootstrap Nodes Section
          BootstrapSettingsSection(
            service: widget.service,
            colorTheme: colorTheme,
          ),
            ],
          ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteAccountConfirmation(BuildContext context) async {
    final toxId = widget.service.selfId;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountSelected),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final hasPassword = await Prefs.hasAccountPassword(toxId);
    final confirmWord = hasPassword
        ? null
        : _kDeleteConfirmWords[Random().nextInt(_kDeleteConfirmWords.length)];

    final inputController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.deleteAccount),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(ctx)!.deleteAccountConfirmMessage),
                const SizedBox(height: 16),
                if (hasPassword) ...[
                  Text(AppLocalizations.of(ctx)!.deleteAccountEnterPasswordToConfirm),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inputController,
                    obscureText: true,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(AppLocalizations.of(ctx)!.deleteAccountTypeWordToConfirm),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(ctx)!.deleteAccountConfirmWordPrompt(confirmWord!),
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    confirmWord,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inputController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            TextButton(
              onPressed: () async {
                if (hasPassword) {
                  final password = inputController.text;
                  final isValid = await Prefs.verifyAccountPassword(toxId, password);
                  if (!isValid) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(ctx)!.invalidPassword),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                        ),
                      );
                    }
                    return;
                  }
                } else {
                  final input = inputController.text.trim().toLowerCase();
                  if (input != confirmWord!.toLowerCase()) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(ctx)!.deleteAccountWrongWord),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                        ),
                      );
                    }
                    return;
                  }
                }
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(true);
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(AppLocalizations.of(ctx)!.delete),
            ),
          ],
        );
      },
    );

    inputController.dispose();

    if (confirmed == true && mounted) {
      await _deleteAccount(context);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Get current account toxId before clearing state
      final toxId = await Prefs.getCurrentAccountToxId();

      // Comprehensive account deletion via AccountService
      if (toxId != null && toxId.isNotEmpty) {
        await AccountService.deleteAccountCompletely(
          service: widget.service,
          toxId: toxId,
        );
      } else {
        // Fallback: just teardown session
        await AccountService.teardownCurrentSession(
          service: widget.service,
          reEncryptProfile: false,
        );
      }

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Navigate to login page and clear navigation stack
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();
      
      // Show error message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.deleteAccountFailed(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _HoverableSettingsRow extends StatefulWidget {
  const _HoverableSettingsRow({required this.child});
  final Widget child;
  @override
  State<_HoverableSettingsRow> createState() => _HoverableSettingsRowState();
}

class _HoverableSettingsRowState extends State<_HoverableSettingsRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.04);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _isHovered ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
        ),
        child: widget.child,
      ),
    );
  }
}

class _AccountCardItem extends StatefulWidget {
  const _AccountCardItem({
    required this.account,
    required this.isCurrentAccount,
    required this.colorTheme,
    required this.onSwitch,
    required this.currentChip,
    required this.subtitle,
  });
  final Map<String, String> account;
  final bool isCurrentAccount;
  final dynamic colorTheme;
  final VoidCallback onSwitch;
  final Widget currentChip;
  final Widget subtitle;

  @override
  State<_AccountCardItem> createState() => _AccountCardItemState();
}

class _AccountCardItemState extends State<_AccountCardItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accountNickname = widget.account['nickname'] ?? '';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          color: widget.isCurrentAccount
              ? widget.colorTheme.primaryColor.withValues(alpha: 0.10)
              : (_isHovered ? widget.colorTheme.primaryColor.withValues(alpha: 0.06) : null),
        ),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: widget.isCurrentAccount
                  ? widget.colorTheme.primaryColor
                  : widget.colorTheme.secondaryColor,
              child: Text(
                accountNickname.isNotEmpty
                    ? accountNickname[0].toUpperCase()
                    : 'A',
                style: TextStyle(
                  color: widget.isCurrentAccount
                      ? widget.colorTheme.onPrimary
                      : widget.colorTheme.onSecondary,
                ),
              ),
            ),
            title: Text(accountNickname.isNotEmpty ? accountNickname : 'Unnamed Account'),
            subtitle: widget.subtitle,
            trailing: widget.isCurrentAccount ? widget.currentChip : IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: widget.onSwitch,
              tooltip: AppLocalizations.of(context)!.switchToThisAccount,
            ),
          ),
        ),
      ),
    );
  }
}