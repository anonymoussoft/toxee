import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/builders/tencent_cloud_chat_common_builders.dart';
import 'package:tencent_cloud_chat_common/log/tencent_cloud_chat_log.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/widgets/avatar/tencent_cloud_chat_avatar.dart';
import 'package:tencent_cloud_chat_common/widgets/dialog/tencent_cloud_chat_dialog.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

import '../../util/app_paths.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Capture+install+restore for toxee's group-profile builder overrides.
///
/// We do NOT snapshot the previous builder closures here. The upstream
/// `setBuilders(...)` is destructive (any slot not passed is nulled), and
/// each slot falls through to a hard-coded upstream default widget when null.
/// So `restore()` just calls `setBuilders()` with no args, which nulls all
/// slots and reverts the manager to upstream defaults — exactly the state
/// before `installOverrides()`. Capturing closures over `manager.getXxx`
/// would create a self-referential loop after restore (the closure ends up
/// dispatching back into itself via the manager) and stack-overflow on next
/// access; this design avoids that.
class GroupProfileBuilderOverrideHandle {
  GroupProfileBuilderOverrideHandle._();

  bool _restored = false;

  static GroupProfileBuilderOverrideHandle capture() {
    return GroupProfileBuilderOverrideHandle._();
  }

  void installOverrides() {
    TencentCloudChatGroupProfileManager.builder.setBuilders(
      groupProfileAvatarBuilder: ({
        required V2TimGroupInfo groupInfo,
        required List<V2TimGroupMemberFullInfo> groupMember,
      }) =>
          _ToxeeGroupProfileAvatar(groupInfo: groupInfo),
      groupProfileChatButtonBuilder: ({
        required V2TimGroupInfo groupInfo,
        VoidCallback? startVideoCall,
        VoidCallback? startVoiceCall,
      }) =>
          _ToxeeGroupProfileChatButton(groupInfo: groupInfo),
      groupProfileContentBuilder: ({required V2TimGroupInfo groupInfo}) =>
          _ToxeeGroupProfileContent(groupInfo: groupInfo),
      groupProfileDeleteButtonBuilder: ({
        required V2TimGroupInfo groupInfo,
        required List<V2TimGroupMemberFullInfo> groupMemberList,
      }) =>
          _ToxeeGroupProfileDeleteButton(
            groupInfo: groupInfo,
            groupMemberList: groupMemberList,
          ),
    );
  }

  void restore() {
    if (_restored) return;
    _restored = true;
    TencentCloudChatGroupProfileManager.builder.setBuilders();
  }
}

/// Group profile avatar. The upstream `ChooseGroupAvatar` flow shows a grid
/// of Tencent server-hosted preset URLs, which is meaningless against Tox
/// conferences. We instead let any group member (the user) pick a local
/// image file; the chosen path is written to `Prefs.setGroupAvatar` and the
/// fake provider stack picks it up via `Prefs.getGroupAvatar` on the next
/// conversation/profile render, so the new avatar is visible app-wide.
///
/// This is per-account + per-device — Tox conferences have no shared
/// avatar concept, so customization stays purely local.
class _ToxeeGroupProfileAvatar extends StatefulWidget {
  final V2TimGroupInfo groupInfo;

  const _ToxeeGroupProfileAvatar({required this.groupInfo});

  @override
  State<_ToxeeGroupProfileAvatar> createState() =>
      _ToxeeGroupProfileAvatarState();
}

class _ToxeeGroupProfileAvatarState extends State<_ToxeeGroupProfileAvatar> {
  late String _faceUrl;
  int _version = 0; // cache-buster forces avatar rebuild after a swap
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _faceUrl = widget.groupInfo.faceUrl ?? '';
    // Resolve the override path (if any) on first build so the dialog
    // reflects the same picture seen elsewhere in the app. Falls back to
    // whatever the upstream `groupInfo.faceUrl` already had.
    unawaited(_loadOverride());
  }

  Future<void> _loadOverride() async {
    try {
      final stored = await Prefs.getGroupAvatar(widget.groupInfo.groupID);
      if (!mounted) return;
      if (stored != null && stored.isNotEmpty && stored != _faceUrl) {
        setState(() => _faceUrl = stored);
      }
    } catch (e) {
      AppLogger.warn('[GroupAvatar] load override failed: $e');
    }
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result =
          await FilePicker.platform.pickFiles(type: FileType.image);
      final pickedPath = result?.files.single.path;
      if (pickedPath == null) return; // user cancelled

      // Stage the file inside the per-account avatars directory so it
      // survives across app launches and is wiped on account removal,
      // matching the self/friend avatar layout from
      // `pickAndPersistAvatar`.
      final currentToxId = await Prefs.getCurrentAccountToxId();
      final avatarsDirPath =
          (currentToxId != null && currentToxId.isNotEmpty)
              ? await AppPaths.getAccountAvatarsPath(currentToxId)
              : (await AppPaths.avatars).path;
      final avatarsDir = Directory(avatarsDirPath);
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }
      final ext = p.extension(pickedPath);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'group_${widget.groupInfo.groupID}_$ts$ext';
      final destPath = p.join(avatarsDirPath, fileName);

      // Best-effort cleanup of older group_<id>_* files so they don't pile
      // up on disk every time the user re-picks. Tolerates locked files.
      try {
        final prefix = 'group_${widget.groupInfo.groupID}_';
        await for (final entity in avatarsDir.list()) {
          if (entity is File && p.basename(entity.path).startsWith(prefix)) {
            try {
              await entity.delete();
            } catch (e) {
              AppLogger.warn(
                  '[GroupAvatar] delete stale ${entity.path} failed: $e');
            }
          }
        }
      } catch (e) {
        AppLogger.warn('[GroupAvatar] stale cleanup scan failed: $e');
      }

      await File(pickedPath).copy(destPath);
      await Prefs.setGroupAvatar(widget.groupInfo.groupID, destPath);

      if (!mounted) return;
      setState(() {
        _faceUrl = destPath;
        _version++;
      });
    } catch (e, st) {
      AppLogger.logError('[GroupAvatar] pick failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to update avatar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // GestureDetector outside the avatar builder so the entire 94×94
        // circle is tappable, not just any nested hit-test region inside
        // the upstream `getCommonAvatarBuilder` widget tree.
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              // `getCommonAvatarBuilder` returns a widget without exposing
              // a `key` slot, so we wrap it in a KeyedSubtree to force a
              // rebuild whenever `_version` bumps after a re-pick. Without
              // this, callers caching by image bytes can show stale art.
              KeyedSubtree(
                key: ValueKey(
                    'group_avatar_${widget.groupInfo.groupID}_$_version'),
                child: TencentCloudChatCommonBuilders.getCommonAvatarBuilder(
                  scene: TencentCloudChatAvatarScene.groupProfile,
                  imageList: [_faceUrl],
                  width: 94,
                  height: 94,
                  borderRadius: 48,
                ),
              ),
              // Small camera badge to hint that the avatar is tappable;
              // without it the area looks purely decorative.
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: _saving
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToxeeGroupProfileChatButton extends StatefulWidget {
  final V2TimGroupInfo groupInfo;

  const _ToxeeGroupProfileChatButton({required this.groupInfo});

  @override
  State<StatefulWidget> createState() => _ToxeeGroupProfileChatButtonState();
}

class _ToxeeGroupProfileChatButtonState
    extends TencentCloudChatState<_ToxeeGroupProfileChatButton> {
  Future<void> _navigateToChat() async {
    await TencentCloudChat.instance.dataInstance.contact.contactEventHandlers
        ?.uiEventHandlers.onNavigateToChat
        ?.call(userID: null, groupID: widget.groupInfo.groupID);
  }

  Widget _buildClickableItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Material(
        color: Colors.transparent,
        child: Container(
          width: getWidth(110),
          decoration: BoxDecoration(
            color: colorTheme.profileChatButtonBackground,
            boxShadow: [
              BoxShadow(
                color: colorTheme.profileChatButtonBoxShadow,
                offset: const Offset(0, 3),
                blurRadius: 6,
              ),
            ],
            borderRadius: BorderRadius.circular(getSquareSize(12)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(getSquareSize(12)),
              child: Container(
                padding: EdgeInsets.all(getSquareSize(16)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      margin: EdgeInsets.only(bottom: getHeight(8)),
                      child: Icon(
                        icon,
                        size: getSquareSize(30),
                        color: colorTheme.primaryColor,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: colorTheme.primaryTextColor,
                        fontSize: textStyle.fontsize_16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Container(
        margin: EdgeInsets.only(top: getHeight(14), bottom: getHeight(40)),
        padding: EdgeInsets.symmetric(horizontal: getSquareSize(16)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildClickableItem(
              icon: Icons.message_rounded,
              label: tL10n.sendMsg,
              onTap: _navigateToChat,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToxeeGroupProfileContent extends StatefulWidget {
  final V2TimGroupInfo groupInfo;

  const _ToxeeGroupProfileContent({required this.groupInfo});

  @override
  State<StatefulWidget> createState() => _ToxeeGroupProfileContentState();
}

class _ToxeeGroupProfileContentState
    extends TencentCloudChatState<_ToxeeGroupProfileContent> {
  String groupName = "";
  String displayGroupID = "";
  String? chatId;
  // Set when `dispose()` runs so the chat-ID retry loop (1+2+3+5+8 = 19 s of
  // cumulative delay) can short-circuit. Without this, every group-profile
  // close used to keep firing FFI lookups for up to 19 seconds against a
  // dead widget.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    displayGroupID = widget.groupInfo.groupID;
    groupName = widget.groupInfo.groupName ?? widget.groupInfo.groupID;
    _loadGroupNameAndID();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadGroupNameAndID() async {
    dynamic ffiService;
    dynamic prefs;

    try {
      final sdkPlatform = TencentCloudChatSdkPlatform.instance;
      final dynamic platform = sdkPlatform;
      try {
        ffiService = platform.ffiService;
        prefs = platform.preferencesService;
      } catch (e) {
        TencentCloudChat.instance.logInstance.console(
          componentName: 'GroupProfile',
          logs: 'Could not access ffiService/preferencesService: $e',
          logLevel: TencentCloudChatLogLevel.error,
        );
      }
    } catch (e) {
      TencentCloudChat.instance.logInstance.console(
        componentName: 'GroupProfile',
        logs: 'Error accessing SDK Platform: $e',
        logLevel: TencentCloudChatLogLevel.error,
      );
    }

    if (prefs != null) {
      try {
        final realGroupName =
            await prefs.getGroupName(widget.groupInfo.groupID);
        if (realGroupName != null &&
            realGroupName.isNotEmpty &&
            realGroupName != widget.groupInfo.groupID) {
          safeSetState(() {
            groupName = realGroupName;
          });
        } else {
          safeSetState(() {
            groupName = widget.groupInfo.groupName ?? widget.groupInfo.groupID;
          });
        }
      } catch (e) {
        TencentCloudChat.instance.logInstance.console(
          componentName: 'GroupProfile',
          logs: 'Error accessing preferences: $e',
          logLevel: TencentCloudChatLogLevel.error,
        );
        safeSetState(() {
          groupName = widget.groupInfo.groupName ?? widget.groupInfo.groupID;
        });
      }
    } else {
      safeSetState(() {
        groupName = widget.groupInfo.groupName ?? widget.groupInfo.groupID;
      });
    }

    if (ffiService != null) {
      unawaited(_tryGetConferenceIdWithRetry(ffiService,
          maxRetries: 5, retryDelay: const Duration(seconds: 1)));
    }

    safeSetState(() {
      displayGroupID = widget.groupInfo.groupID;
    });
  }

  Future<void> _tryGetConferenceIdWithRetry(
    dynamic ffiService, {
    int maxRetries = 5,
    required Duration retryDelay,
  }) async {
    final retryDelays = [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 3),
      const Duration(seconds: 5),
      const Duration(seconds: 8),
    ];

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (_disposed) return;
      try {
        final retrievedChatId =
            (ffiService as dynamic).getGroupChatId(widget.groupInfo.groupID);
        if (retrievedChatId != null &&
            retrievedChatId is String &&
            retrievedChatId.isNotEmpty) {
          safeSetState(() {
            chatId = retrievedChatId;
            displayGroupID = widget.groupInfo.groupID;
          });
          return;
        } else {
          if (attempt < maxRetries - 1) {
            final delay = attempt < retryDelays.length
                ? retryDelays[attempt]
                : retryDelay;
            await Future.delayed(delay);
            if (_disposed) return;
          }
        }
      } catch (e) {
        TencentCloudChat.instance.logInstance.console(
          componentName: 'GroupProfile',
          logs: 'Error getting chat ID: $e',
          logLevel: TencentCloudChatLogLevel.error,
        );
        if (attempt < maxRetries - 1) {
          final delay = attempt < retryDelays.length
              ? retryDelays[attempt]
              : retryDelay;
          await Future.delayed(delay);
          if (_disposed) return;
        }
      }
    }
  }

  Future<void> _onChangeGroupName(String value) async {
    final res = await TencentCloudChat.instance.chatSDKInstance.groupSDK
        .setGroupInfo(
            groupID: widget.groupInfo.groupID,
            groupType: widget.groupInfo.groupType,
            groupName: value);
    if (res.code == 0) {
      safeSetState(() {
        groupName = value;
      });
    }
  }

  void _changeGroupName() {
    final controller = TextEditingController(text: groupName);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tL10n.setGroupName),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tL10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) {
                  Navigator.pop(dialogContext);
                  return;
                }
                _onChangeGroupName(trimmed);
                Navigator.pop(dialogContext);
              },
              child: Text(tL10n.confirm),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Container(
        padding: EdgeInsets.all(getSquareSize(16)),
        child: Column(
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    groupName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: textStyle.fontsize_24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  FloatingActionButton.small(
                    onPressed: _changeGroupName,
                    elevation: 0,
                    backgroundColor: colorTheme.contactBackgroundColor,
                    child: Icon(
                      Icons.border_color_rounded,
                      color: colorTheme.contactBackButtonColor,
                      size: getSquareSize(15),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: getHeight(8)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                chatId != null && chatId!.isNotEmpty
                    ? "Group ID: $chatId"
                    : "Group ID: $displayGroupID",
                style: TextStyle(
                  fontSize: textStyle.fontsize_12,
                  color: chatId != null && chatId!.isNotEmpty
                      ? colorTheme.groupProfileTextColor
                      : colorTheme.groupProfileTextColor.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToxeeGroupProfileDeleteButton extends StatefulWidget {
  final V2TimGroupInfo groupInfo;
  final List<V2TimGroupMemberFullInfo> groupMemberList;

  const _ToxeeGroupProfileDeleteButton({
    required this.groupInfo,
    required this.groupMemberList,
  });

  @override
  State<StatefulWidget> createState() => _ToxeeGroupProfileDeleteButtonState();
}

class _ToxeeGroupProfileDeleteButtonState
    extends TencentCloudChatState<_ToxeeGroupProfileDeleteButton> {
  bool quitGroup = true;

  @override
  void initState() {
    super.initState();
    _checkIfQuitGroup();
  }

  void _checkIfQuitGroup() {
    if (widget.groupInfo.groupType != GroupType.Work &&
        widget.groupInfo.role ==
            GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER) {
      quitGroup = false;
    }
  }

  void _showClearChatHistoryDialog() {
    TencentCloudChatDialog.showAdaptiveDialog(
      context: context,
      title: Text(tL10n.clearMsgTip),
      actions: <Widget>[
        TextButton(
          child: Text(tL10n.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text(tL10n.confirm),
          onPressed: () {
            Navigator.of(context).pop(true);
            _onClearChatHistory();
          },
        ),
      ],
    );
  }

  Future<void> _onClearChatHistory() async {
    final res = await TencentCloudChat.instance.chatSDKInstance.groupSDK
        .clearGroupHistoryMessage(groupID: widget.groupInfo.groupID);
    if (res.code == 0) {
      TencentCloudChat.instance.dataInstance.messageData
          .clearMessageList(groupID: widget.groupInfo.groupID);
    }
  }

  void _showQuitGroupDialog() {
    TencentCloudChatDialog.showAdaptiveDialog(
      context: context,
      title: quitGroup ? Text(tL10n.quitGroupTip) : Text(tL10n.dismissGroupTip),
      actions: <Widget>[
        TextButton(
          child: Text(tL10n.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text(tL10n.confirm),
          onPressed: () {
            Navigator.of(context).pop(true);
            _handleQuitGroup();
          },
        ),
      ],
    );
  }

  Future<void> _handleQuitGroup() async {
    late V2TimCallback result;
    if (quitGroup == true) {
      result = await TencentCloudChat.instance.chatSDKInstance.groupSDK
          .quitGroup(groupID: widget.groupInfo.groupID);
    } else {
      result = await TencentCloudChat.instance.chatSDKInstance.groupSDK
          .dismissGroup(groupID: widget.groupInfo.groupID);
    }

    if (result.code == 0 && mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Column(
        children: [
          Container(
            width: double.infinity,
            color: colorTheme.groupProfileTabBackground,
            padding: EdgeInsets.symmetric(
                vertical: getHeight(10), horizontal: getWidth(16)),
            child: GestureDetector(
              onTap: _showClearChatHistoryDialog,
              child: Text(
                tL10n.deleteAllMessages,
                style: TextStyle(
                  color: colorTheme.contactRefuseButtonColor,
                  fontSize: textStyle.fontsize_16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Container(
            margin: EdgeInsets.only(top: getHeight(1)),
            color: colorTheme.groupProfileTabBackground,
            width: double.infinity,
            padding: EdgeInsets.symmetric(
                vertical: getHeight(10), horizontal: getWidth(16)),
            child: GestureDetector(
              onTap: _showQuitGroupDialog,
              child: Text(
                quitGroup ? tL10n.quit : tL10n.dissolve,
                style: TextStyle(
                  color: colorTheme.contactRefuseButtonColor,
                  fontSize: textStyle.fontsize_16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
