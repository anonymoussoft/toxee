import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import '../util/app_theme_config.dart';
import '../i18n/app_localizations.dart';

class AddGroupDialog extends StatefulWidget {
  const AddGroupDialog({
    super.key,
    required this.service,
    this.onGroupChanged,
    this.onShowSnackBar,
  });

  final FfiChatService service;
  final Future<void> Function(String groupId, {String? displayName})? onGroupChanged;
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
  String _selectedGroupType = 'group'; // 'group' or 'conference'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestController.text.isEmpty) {
      _requestController.text = AppLocalizations.of(context)!.defaultJoinRequestMessage;
    }
  }

  @override
  void dispose() {
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
    setState(() => _isJoining = true);
    try {
      await widget.service.joinGroup(gid, requestMessage: wording);
      if (alias.isNotEmpty) {
        await Prefs.setGroupName(gid, alias);
      }
      await widget.onGroupChanged?.call(gid, displayName: alias.isNotEmpty ? alias : null);
      _notify(_localeText(context, 'joinSuccess', fallback: 'Join request sent'));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _notify('${_localeText(context, 'joinFailed', fallback: 'Join failed')}: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    if (!_createFormKey.currentState!.validate()) return;
    final name = _createNameController.text.trim();
    setState(() => _isCreating = true);
    try {
      final gid = await widget.service.createGroup(name, groupType: _selectedGroupType);
      if (gid == null || gid.isEmpty) {
        _notify(_localeText(context, 'createFailed', fallback: 'Failed to create group'));
        return;
      }
      await Prefs.setGroupName(gid, name);
      await widget.onGroupChanged?.call(gid, displayName: name);
      setState(() => _createdGroupId = gid);
      _notify(_localeText(context, 'createSuccess', fallback: 'Group created'));
      // Close dialog after successful creation
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _notify('${_localeText(context, 'createFailed', fallback: 'Failed to create group')}: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 560.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localeText(context, 'addGroup', fallback: 'Add or Create Group'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildJoinCard(colorTheme),
                  const SizedBox(height: 16),
                  _buildCreateCard(colorTheme),
                  if (_createdGroupId != null) ...[
                    const SizedBox(height: 16),
                    _buildCreatedInfo(colorTheme),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinCard(colorTheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        side: BorderSide(color: colorTheme.dividerColor),
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
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _joinFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'joinGroup', fallback: 'Join Group by ID'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _groupIdController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupId', fallback: 'Group ID'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return _localeText(context, 'enterGroupId', fallback: 'Please enter group ID');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _requestController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'requestMessage', fallback: 'Request Message'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
                minLines: 1,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _aliasController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupAlias', fallback: 'Local group name (optional)'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                    ),
                  ),
                  icon: _isJoining
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.group_add),
                  label: Text(_localeText(context, 'joinAction', fallback: 'Send Join Request')),
                  onPressed: _isJoining ? null : _joinGroup,
                ),
              ),
            ],
          ),
        ),
        ),
        ],
      ),
    );
  }

  Widget _buildCreateCard(colorTheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        side: BorderSide(color: colorTheme.dividerColor),
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
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _createFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'createGroup', fallback: 'Create New Group'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _createNameController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupName', fallback: 'Group Name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return _localeText(context, 'enterGroupName', fallback: 'Please enter a group name');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                _localeText(context, 'groupType', fallback: 'Group Type'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'group',
                    label: Text(AppLocalizations.of(context)!.group),
                    icon: const Icon(Icons.group),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                    ),
                  ),
                  icon: _isCreating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.group),
                  label: Text(_localeText(context, 'createAction', fallback: 'Create Group')),
                  onPressed: _isCreating ? null : _createGroup,
                ),
              ),
            ],
          ),
        ),
        ),
        ],
      ),
    );
  }

  Widget _buildCreatedInfo(colorTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTheme.secondaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localeText(context, 'createdGroupId', fallback: 'New Group ID'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(_createdGroupId ?? ''),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(_localeText(context, 'copyId', fallback: 'Copy ID')),
            onPressed: _createdGroupId == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _createdGroupId!));
                    _notify(_localeText(context, 'copied', fallback: 'Copied to clipboard'));
                  },
          ),
        ],
      ),
    );
  }

  void _notify(String message) {
    if (widget.onShowSnackBar != null) {
      widget.onShowSnackBar!(message);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _localeText(BuildContext context, String key, {required String fallback}) {
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
    }
    return fallback;
  }
}

