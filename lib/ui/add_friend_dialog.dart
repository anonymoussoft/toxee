import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({
    super.key,
    required this.service,
    this.onFriendAdded,
    this.onShowSnackBar,
  });

  final FfiChatService service;
  final Future<void> Function(String friendId)? onFriendAdded;
  final void Function(String message)? onShowSnackBar;

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  late final TextEditingController _messageController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Initialize message controller with default message
    // Use a default English message as fallback, will be updated in build
    _messageController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set default message after context is available
    if (_messageController.text.isEmpty) {
      _messageController.text = AppLocalizations.of(context)!.defaultFriendRequestMessage;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    final rawId = _idController.text.trim();
    final message = _messageController.text.trim();
    
    // Ensure message is not empty
    if (message.isEmpty) {
      _notify(_localeText(context, 'enterMessage', fallback: 'Please enter a message'));
      return;
    }
    
    setState(() => _isSubmitting = true);
    try {
      await widget.service.addFriend(rawId, requestMessage: message);
      await widget.onFriendAdded?.call(rawId);
      _notify(_localeText(context, 'requestSent', fallback: 'Friend request sent'));
      _idController.clear();
      _messageController.text = AppLocalizations.of(context)!.defaultFriendRequestMessage;
      // Close dialog after successful submission
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _notify('${_localeText(context, 'requestFailed', fallback: 'Failed')}: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateToxId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(context, 'enterId', fallback: 'Please enter a Tox ID');
    }
    // Accept 64 (public key) or 76 (full address). Keep 76 as-is - Tox friend request
    // spam mechanism relies on nospam+checksum in the full address.
    if (trimmed.length < 64) {
      return _localeText(context, 'invalidLength', fallback: 'ID must be at least 64 hex characters');
    }
    final hexRegex = RegExp(r'^[0-9A-Fa-f]+$');
    if (!hexRegex.hasMatch(trimmed)) {
      return _localeText(context, 'invalidHex', fallback: 'Only hexadecimal characters are allowed');
    }
    return null;
  }

  String? _validateMessage(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(context, 'enterMessage', fallback: 'Please enter a message');
    }
    // TOX_MAX_FRIEND_REQUEST_LENGTH = 921
    const maxLength = 921;
    if (trimmed.length > maxLength) {
      return AppLocalizations.of(context)!.friendRequestMessageTooLong;
    }
    return null;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() {
        _idController.text = data!.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 520.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
            ),
            clipBehavior: Clip.antiAlias,
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
                      _localeText(context, 'addContact', fallback: 'Add Contact'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _localeText(
                        context,
                        'addContactHint',
                        fallback: 'Enter the peer Tox ID (at least 64 hex characters, or 76 for full address).',
                      ),
                      style: TextStyle(color: colorTheme.secondaryTextColor),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _idController,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        labelText: _localeText(context, 'friendUserID', fallback: 'Friend Tox ID'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste),
                          tooltip: _localeText(context, 'paste', fallback: 'Paste'),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                      validator: _validateToxId,
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _messageController,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        labelText: _localeText(context, 'requestMessage', fallback: 'Request Message'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                        ),
                        helperText: '${_messageController.text.length}/921',
                      ),
                      validator: _validateMessage,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (value) {
                        setState(() {}); // Update helper text
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                          ),
                        ),
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(_localeText(context, 'addContact', fallback: 'Add Contact')),
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _localeText(BuildContext context, String key, {required String fallback}) {
    final t = TencentCloudChatLocalizations.of(context);
    final appL10n = AppLocalizations.of(context)!;
    switch (key) {
      case 'addContact':
        return t?.addContact ?? fallback;
      case 'friendUserID':
        return t?.userID ?? fallback;
      case 'requestSent':
        return t?.requestSent ?? fallback;
      case 'requestFailed':
        return appL10n.addFailed;
      case 'enterId':
        return appL10n.enterId;
      case 'invalidLength':
        return appL10n.invalidLength;
      case 'invalidHex':
        return appL10n.invalidCharacters;
      case 'paste':
        return appL10n.paste;
      case 'addContactHint':
        return appL10n.addContactHint;
      case 'requestMessage':
        return appL10n.verificationMessage;
      case 'enterMessage':
        return appL10n.enterMessage;
    }
    return fallback;
  }

  void _notify(String message) {
    if (widget.onShowSnackBar != null) {
      widget.onShowSnackBar!(message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

