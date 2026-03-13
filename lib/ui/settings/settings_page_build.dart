part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  List<Widget> _buildSettingsChildren(BuildContext context, dynamic colorTheme) {
    return [
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
                SectionHeader(title: AppLocalizations.of(context)!.accountManagement),
                const SizedBox(height: 8),
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
                        : (_accountList.length > _SettingsPageState._accountListPreviewCount
                            ? _SettingsPageState._accountListPreviewCount
                            : _accountList.length),
                    itemBuilder: (context, index) {
                      final account = _accountList[index];
                      final accountToxId = account['toxId'] ?? '';
                      final lastLogin = account['lastLoginTime'];
                      // Use Prefs current Tox ID; widget.service.selfId is UIKit placeholder (e.g. FlutterUIKitClient)
                      final currentId = _currentAccountToxId ?? widget.service.selfId;
                      final isCurrentAccount = compareToxIds(accountToxId, currentId);
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
                  if (_accountList.length > _SettingsPageState._accountListPreviewCount) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _settingsSetState(() => _accountListExpanded = !_accountListExpanded),
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
                                  : AppLocalizations.of(context)!.showMore(_accountList.length - _SettingsPageState._accountListPreviewCount),
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
      GlobalSettingsSection(
        colorTheme: colorTheme,
        toxId: widget.service.selfId,
      ),
      const SizedBox(height: 12),
      BootstrapSettingsSection(
        service: widget.service,
        colorTheme: colorTheme,
      ),
    ];
  }
}
