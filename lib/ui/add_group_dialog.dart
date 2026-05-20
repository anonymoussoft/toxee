import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/app_spacing.dart';
import '../util/prefs.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import '../i18n/app_localizations.dart';

// Per-form-factor dialog widths. The wider tablet/desktop caps give the two
// stacked cards (join + create) room to breathe instead of forcing a tall
// narrow column on landscape tablets and desktop windows.
const double _kMobileMaxDialogWidth = 560;
const double _kTabletMaxDialogWidth = 720;
const double _kDesktopMaxDialogWidth = 820;

double _dialogMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (ResponsiveLayout.isDesktop(context)) {
    return (w - 64).clamp(280.0, _kDesktopMaxDialogWidth);
  }
  if (ResponsiveLayout.isTabletLandscape(context)) {
    return (w - 48).clamp(280.0, _kDesktopMaxDialogWidth);
  }
  if (ResponsiveLayout.isTablet(context)) {
    return (w - 48).clamp(280.0, _kTabletMaxDialogWidth);
  }
  return (w - 32).clamp(280.0, _kMobileMaxDialogWidth);
}

class AddGroupDialog extends StatefulWidget {
  const AddGroupDialog({
    super.key,
    required this.service,
    this.onGroupChanged,
    this.onShowSnackBar,
  });

  final FfiChatService service;
  final Future<void> Function(String groupId, {String? displayName})?
      onGroupChanged;
  final void Function(String message)? onShowSnackBar;

  @override
  State<AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<AddGroupDialog> {
  final _joinFormKey = GlobalKey<FormState>();
  final _createFormKey = GlobalKey<FormState>();
  final _groupIdController = TextEditingController();
  final _requestController = TextEditingController();
  final _aliasController = TextEditingController();
  final _createNameController = TextEditingController();
  bool _isJoining = false;
  bool _isCreating = false;
  String? _createdGroupId;
  // Selected create-group type:
  //  - 'group'      → new-API Tox group, PUBLIC (DHT-announced)
  //  - 'privateGroup' → new-API Tox group, PRIVATE (friend-invite only)
  //  - 'conference' → legacy Tox conference
  String _selectedGroupType = 'group';
  bool _isConnected = true;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _isConnected = widget.service.isConnected;
    _connSub = widget.service.connectionStatusStream.listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestController.text.isEmpty) {
      _requestController.text =
          AppLocalizations.of(context)!.defaultJoinRequestMessage;
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _groupIdController.dispose();
    _requestController.dispose();
    _aliasController.dispose();
    _createNameController.dispose();
    super.dispose();
  }

  Future<void> _joinGroup() async {
    if (_isJoining) return;
    if (!_joinFormKey.currentState!.validate()) return;
    final gid = _groupIdController.text.trim();
    final wording = _requestController.text.trim();
    final alias = _aliasController.text.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final successText =
        _localeText(context, 'joinSuccess', fallback: 'Join request sent');
    final queuedText = _localeText(context, 'joinQueued',
        fallback: 'Offline — join request will be sent when you reconnect');
    final failurePrefix =
        _localeText(context, 'joinFailed', fallback: 'Join failed');

    setState(() => _isJoining = true);
    try {
      await widget.service.joinGroup(gid, requestMessage: wording);
      // Local alias only — do NOT clobber the canonical group name. When
      // the canonical name arrives from peers later, the alias still takes
      // display precedence via Prefs.resolveGroupDisplayName.
      if (alias.isNotEmpty) {
        await Prefs.setGroupAlias(gid, alias);
      }
      await widget.onGroupChanged?.call(gid,
          displayName: alias.isNotEmpty ? alias : null);
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, _isConnected ? successText : queuedText);
      if (mounted) {
        await navigator.maybePop();
      }
    } catch (e) {
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, '$failurePrefix: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    if (!_createFormKey.currentState!.validate()) return;
    final name = _createNameController.text.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final createFailedText = _localeText(context, 'createFailed',
        fallback: 'Failed to create group');
    final createSuccessText =
        _localeText(context, 'createSuccess', fallback: 'Group created');

    setState(() => _isCreating = true);
    try {
      // Translate UI selection to the type string the C++ side expects.
      // Note: 'group' historically maps to PRIVATE in dart_compat_group.cpp,
      // which contradicts the PUBLIC labeling we want here. Pass 'Public'
      // explicitly so the mapping is unambiguous; the C++ side recognizes
      // 'Public' → PUBLIC group.
      final typeForFfi = switch (_selectedGroupType) {
        'group' => 'Public',
        'privateGroup' => 'Private',
        'conference' => 'conference',
        _ => 'Public',
      };
      final gid = await widget.service
          .createGroup(name, groupType: typeForFfi);
      if (gid == null || gid.isEmpty) {
        await HapticFeedback.lightImpact();
        _notifyVia(messenger, createFailedText);
        return;
      }
      await Prefs.setGroupName(gid, name);
      await widget.onGroupChanged?.call(gid, displayName: name);
      if (!mounted) return;
      setState(() => _createdGroupId = gid);
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, createSuccessText);
      // Close dialog after successful creation
      if (mounted) {
        await navigator.maybePop();
      }
    } catch (e) {
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, '$createFailedText: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _pasteGroupId() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final pasted = data?.text?.trim();
    if (pasted != null && pasted.isNotEmpty) {
      setState(() {
        _groupIdController.text = pasted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => CallbackShortcuts(
        // D1: Esc closes the dialog. Enter is intentionally not bound
        // because this dialog has two forms (join + create) and a default
        // Enter binding would be ambiguous.
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_isJoining || _isCreating) return;
            Navigator.of(context).maybePop();
          },
        },
        child: Focus(
          autofocus: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _dialogMaxWidth(context)),
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localeText(context, 'addGroup',
                            fallback: 'Add or Create Group'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                      ),
                      if (!_isConnected) ...[
                        AppSpacing.verticalMd,
                        _OfflineBanner(
                          message: _localeText(
                            context,
                            'offlineBanner',
                            fallback:
                                'Offline — group operations will be queued and processed when you reconnect.',
                          ),
                        ),
                      ],
                      AppSpacing.verticalLg,
                      _buildJoinCard(),
                      AppSpacing.verticalLg,
                      _buildCreateCard(),
                      if (_createdGroupId != null) ...[
                        AppSpacing.verticalLg,
                        _buildCreatedInfo(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _joinFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'joinGroup',
                    fallback: 'Join Group by ID'),
                style: theme.textTheme.titleMedium,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _groupIdController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupId',
                      fallback: 'Group ID'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                  // D4: paste button to match the add-friend dialog ergonomics.
                  // Group IDs are long opaque strings; users almost always
                  // paste them rather than type them.
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip:
                        _localeText(context, 'paste', fallback: 'Paste'),
                    onPressed: _pasteGroupId,
                  ),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return _localeText(context, 'enterGroupId',
                        fallback: 'Please enter group ID');
                  }
                  return null;
                },
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _requestController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'requestMessage',
                      fallback: 'Request Message'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
                minLines: 1,
                maxLines: 4,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _aliasController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupAlias',
                      fallback: 'Local group name (optional)'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
              ),
              AppSpacing.verticalLg,
              _buildPrimaryAction(
                scheme: scheme,
                busy: _isJoining,
                icon: Icons.group_add,
                label: _localeText(context, 'joinAction',
                    fallback: 'Send Join Request'),
                onPressed: _joinGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      // Tinted-primary variant signals this is the canonical "create" path.
      color: AppThemeConfig.tintedPrimaryCardColor(scheme.primary),
      shape: AppThemeConfig.tintedPrimaryCardShape(scheme.primary),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _createFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'createGroup',
                    fallback: 'Create New Group'),
                style: theme.textTheme.titleMedium,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _createNameController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupName',
                      fallback: 'Group Name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return _localeText(context, 'enterGroupName',
                        fallback: 'Please enter a group name');
                  }
                  return null;
                },
              ),
              AppSpacing.verticalLg,
              Text(
                _localeText(context, 'groupType', fallback: 'Group Type'),
                style: theme.textTheme.bodyMedium,
              ),
              AppSpacing.verticalSm,
              // P0-B4: three explicit choices instead of two ambiguous ones.
              // Previously the "group" label silently created a PRIVATE group
              // because dart_compat_group.cpp mapped the string "group" → 1
              // (Private). Now we surface Public/Private as separate options
              // and pass the unambiguous type string to the FFI layer.
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'group',
                    label: Text(_localeText(context, 'publicGroup',
                        fallback: 'Public')),
                    icon: const Icon(Icons.public),
                  ),
                  ButtonSegment(
                    value: 'privateGroup',
                    label: Text(_localeText(context, 'privateGroup',
                        fallback: 'Private')),
                    icon: const Icon(Icons.lock),
                  ),
                  ButtonSegment(
                    value: 'conference',
                    label: Text(AppLocalizations.of(context)!.conference),
                    icon: const Icon(Icons.forum),
                  ),
                ],
                selected: {_selectedGroupType},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _selectedGroupType = newSelection.first;
                  });
                },
              ),
              AppSpacing.verticalXs,
              Text(
                _groupTypeHint(_selectedGroupType),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              AppSpacing.verticalLg,
              _buildPrimaryAction(
                scheme: scheme,
                busy: _isCreating,
                icon: Icons.group,
                label: _localeText(context, 'createAction',
                    fallback: 'Create Group'),
                onPressed: _createGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _groupTypeHint(String type) {
    switch (type) {
      case 'group':
        return _localeText(context, 'publicGroupHint',
            fallback:
                'Public group — discoverable on the DHT and joinable by anyone with the chat ID.');
      case 'privateGroup':
        return _localeText(context, 'privateGroupHint',
            fallback:
                'Private group — invitation-only, not announced on the DHT.');
      case 'conference':
        return _localeText(context, 'conferenceHint',
            fallback:
                'Legacy conference — older protocol, no roles or persistence.');
      default:
        return '';
    }
  }

  Widget _buildPrimaryAction({
    required ColorScheme scheme,
    required bool busy,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: busy ? _localeText(context, 'sending', fallback: 'Sending...') : '',
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
          ),
          icon: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                  ),
                )
              : Icon(icon),
          label: Text(label),
          onPressed: busy ? null : onPressed,
        ),
      ),
    );
  }

  Widget _buildCreatedInfo() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppThemeConfig.tintedPrimaryCardColor(scheme.primary),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: AppThemeConfig.tintedPrimaryCardBorderColor(scheme.primary),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localeText(context, 'createdGroupId', fallback: 'New Group ID'),
            style: theme.textTheme.titleMedium,
          ),
          AppSpacing.verticalSm,
          SelectableText(
            _createdGroupId ?? '',
            style:
                theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
          AppSpacing.verticalSm,
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              side: BorderSide(
                color: AppThemeConfig
                    .tintedPrimaryCardBorderColor(scheme.primary),
              ),
            ),
            icon: const Icon(Icons.copy),
            label: Text(_localeText(context, 'copyId', fallback: 'Copy ID')),
            onPressed: _createdGroupId == null
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final copiedText = _localeText(context, 'copied',
                        fallback: 'Copied to clipboard');
                    await Clipboard.setData(
                        ClipboardData(text: _createdGroupId!));
                    _notifyVia(messenger, copiedText);
                  },
          ),
        ],
      ),
    );
  }

  void _notifyVia(ScaffoldMessengerState? messenger, String message) {
    if (widget.onShowSnackBar != null) {
      widget.onShowSnackBar!(message);
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _localeText(BuildContext context, String key,
      {required String fallback}) {
    final appL10n = AppLocalizations.of(context)!;
    switch (key) {
      case 'addGroup':
        return appL10n.addOrCreateGroup;
      case 'joinGroup':
        return appL10n.joinGroupById;
      case 'groupId':
        return appL10n.groupId;
      case 'enterGroupId':
        return appL10n.enterGroupId;
      case 'requestMessage':
        return appL10n.requestMessage;
      case 'groupAlias':
        return appL10n.groupAlias;
      case 'joinAction':
        return appL10n.joinAction;
      case 'joinSuccess':
        return appL10n.joinSuccess;
      case 'joinFailed':
        return appL10n.joinFailed;
      case 'createGroup':
        return appL10n.createGroup;
      case 'groupName':
        return appL10n.groupName;
      case 'enterGroupName':
        return appL10n.enterGroupName;
      case 'createAction':
        return appL10n.createAction;
      case 'createSuccess':
        return appL10n.createSuccess;
      case 'createFailed':
        return appL10n.createFailed;
      case 'createdGroupId':
        return appL10n.createdGroupId;
      case 'copyId':
        return appL10n.copyId;
      case 'copied':
        return appL10n.copied;
      case 'paste':
        return appL10n.paste;
      case 'sending':
        return fallback;
    }
    return fallback;
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
