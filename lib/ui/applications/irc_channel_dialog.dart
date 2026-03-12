import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';

class IrcChannelDialog extends StatefulWidget {
  const IrcChannelDialog({super.key});

  @override
  State<IrcChannelDialog> createState() => _IrcChannelDialogState();
}

class _IrcChannelDialogState extends State<IrcChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _channelController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _channelController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  String? _validateChannel(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      final appL10n = AppLocalizations.of(context);
      return appL10n?.enterIrcChannel ?? 'Please enter IRC channel name';
    }
    // IRC channel names typically start with # or &
    if (!trimmed.startsWith('#') && !trimmed.startsWith('&')) {
      final appL10n = AppLocalizations.of(context);
      return appL10n?.invalidIrcChannel ?? 'IRC channel must start with # or &';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorTheme.primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appL10n?.joinIrcChannel ?? 'Join IRC Channel',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appL10n?.ircChannelName ?? 'IRC Channel Name',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorTheme.primaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _channelController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: appL10n?.ircChannelHint ?? '#channel',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                            ),
                            prefixText: _channelController.text.isEmpty ||
                                _channelController.text.startsWith('#') ||
                                _channelController.text.startsWith('&')
                                ? null
                                : '#',
                          ),
                          validator: _validateChannel,
                          autofocus: true,
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appL10n?.ircChannelPassword ?? 'Channel Password (optional)',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorTheme.primaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: appL10n?.ircChannelPasswordHint ?? 'Leave empty if no password',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          enableSuggestions: false,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appL10n?.ircCustomNickname ?? 'Custom IRC Nickname (optional)',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorTheme.primaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nicknameController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: appL10n?.ircCustomNicknameHint ?? 'Leave empty to use auto-generated nickname',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appL10n?.ircChannelDesc ??
                              'Enter the IRC channel name (e.g., #channel). A Tox group will be created for this channel.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorTheme.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(appL10n?.cancel ?? 'Cancel'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  final channel = _channelController.text.trim();
                                  // Ensure channel starts with # or &
                                  final normalizedChannel =
                                      (channel.startsWith('#') || channel.startsWith('&'))
                                          ? channel
                                          : '#$channel';
                                  final password = _passwordController.text.trim();
                                  final nickname = _nicknameController.text.trim();
                                  // Return channel, password, and nickname as a record
                                  Navigator.of(context).pop((
                                    channel: normalizedChannel,
                                    password: password.isEmpty ? null : password,
                                    nickname: nickname.isEmpty ? null : nickname,
                                  ));
                                }
                              },
                              child: Text(appL10n?.join ?? 'Join'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

