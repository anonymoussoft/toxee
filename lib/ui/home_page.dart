import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/disposable_bag.dart';
import '../util/prefs.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../util/locale_controller.dart';
import '../util/tox_utils.dart';
import '../util/theme_controller.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/fake_models.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_provider.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import '../sdk_fake/fake_msg_provider.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/tuicore/tencent_cloud_chat_core.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_controller.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart' as conv_pkg;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart' as msg_pkg;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_input.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/tencent_cloud_chat_message_item_builders.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart' as contact_pkg;
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';
import 'contact/contact_builder_override.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import '../i18n/app_localizations.dart';
import '../util/logger.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/special_case/tencent_cloud_chat_message_no_chat.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/data/basic/tencent_cloud_chat_basic_data.dart';
import 'package:tencent_cloud_chat_common/data/group_profile/tencent_cloud_chat_group_profile_data.dart';
import 'group/group_member_list_wrapper.dart';
import 'package:tencent_cloud_chat_common/eventbus/tencent_cloud_chat_eventbus.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_router.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_init_data.dart';
import 'package:tencent_cloud_chat_text_translate/tencent_cloud_chat_text_translate.dart';
import 'package:tencent_cloud_chat_sound_to_text/tencent_cloud_chat_sound_to_text.dart';
import 'search/custom_search.dart' as search_pkg;
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'settings/settings_page.dart';
import 'settings/sidebar.dart';
import 'applications/applications_page.dart';
import 'home/home_utils.dart';
import '../util/app_theme_config.dart';
import '../util/app_tray.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/platform_utils.dart';
import 'add_friend_dialog.dart';
import 'add_group_dialog.dart';
import 'home/home_widgets.dart';
import '../util/irc_app_manager.dart';
import 'applications/irc_channel_dialog.dart';
import '../util/responsive_layout.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'widgets/app_snackbar.dart';

part 'home_page_persistence.dart';
part 'home_page_plugins.dart';
part 'home_page_bootstrap.dart';

enum _MediaPickType { image, video }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.service});
  final FfiChatService service;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  bool _globalAdapterInited = false;
  StreamSubscription? _friendsSub;
  StreamSubscription? _appsSub;
  List<({String userId, String nickName, bool online, String status})> _friends = [];
  Timer? _refreshTimer;
  Set<String> _localFriends = {};
  bool _autoAcceptFriends = false;
  bool _autoAcceptGroupInvites = false;
  List<V2TimFriendApplication> _pendingFriendApps = [];
  bool _stickerPluginRegistered = false;
  bool _textTranslatePluginRegistered = false;
  bool _soundToTextPluginRegistered = false;
  StreamSubscription? _msgSub;
  StreamSubscription? _progressUpdatesSub;
  StreamSubscription<bool>? _connectionStatusSub;
  StreamSubscription<TencentCloudChatConversationData<dynamic>>? _conversationDataSub;
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  StreamSubscription<TencentCloudChatGroupProfileData<dynamic>>? _groupProfileDataSub;
  // Track last membersChange event time per groupID to prevent loops
  final Map<String, DateTime> _lastMembersChangeTime = {};
  static const Duration _minMembersChangeInterval = Duration(seconds: 2);
  BuildContext? _scaffoldMessengerContext;
  DateTime? _lastBackPressTime;
  bool _ircAppInstalled = false;
  // Track UniqueKey per conversation to ensure proper widget lifecycle
  final Map<String, UniqueKey> _messageWidgetKeys = {};
  // Track current conversation to force widget rebuild on change
  String? _currentConversationID;
  // Track if we need to skip building widget on next frame to ensure old widget is disposed
  // Removed _skipNextBuild - it was preventing message widget from being built
  // The desktop mode component will rebuild when currentConversation changes
  // Counter to ensure unique keys across conversation switches
  int _messageWidgetKeyCounter = 0;
  
  // LAN bootstrap service state
  bool _lanBootstrapServiceRunning = false;
  String? _lanBootstrapServiceIP;
  int? _lanBootstrapServicePort;
  Timer? _bootstrapServiceStatusTimer;
  final _bag = DisposableBag();
  StreamSubscription<bool>? _persistenceHookSub;
  bool _persistenceHookInstalled = false;
  bool _disposed = false;
  ContactBuilderOverrideHandle? _contactBuilderOverride;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bag.add(() => WidgetsBinding.instance.removeObserver(this));
    // HYBRID MODE: Using both binary replacement (for most operations) and Platform interface (for history queries)
    // This allows:
    // - Most operations to use binary replacement (TIMManager.instance -> NativeLibraryManager -> Dart* functions)
    // - History queries to use Platform interface (Tim2ToxSdkPlatform -> FfiChatService -> MessageHistoryPersistence)
    // This ensures history messages are loaded from persistence service instead of returning empty list from C++ layer
    
    // Session runtime (FakeUIKit, platform, CallServiceManager) via coordinator
    unawaited(_initAfterSessionReady());
  }


  /// Used by home_page_bootstrap.dart extension to call setState (avoids invalid_use_of_protected_member).
  void _bootstrapSetState(VoidCallback fn) {
    setState(fn);
  }

  // Build "Add Friend" button widget for non-friends
  Widget _buildAddFriendButton(V2TimUserFullInfo userFullInfo) {
    return Builder(
      builder: (context) {
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 1,
                  color: colorTheme.backgroundColor,
                ),
              ),
              color: colorTheme.contactAddContactFriendInfoStateButtonBackgroundColor,
            ),
            padding: EdgeInsets.symmetric(
              vertical: TencentCloudChatScreenAdapter.getHeight(10),
              horizontal: TencentCloudChatScreenAdapter.getWidth(16),
            ),
            child: GestureDetector(
              onTap: () => _onAddFriend(context, userFullInfo.userID ?? ''),
              child: Text(
                AppLocalizations.of(context)!.addFriend,
                style: TextStyle(
                  color: colorTheme.primaryColor,
                  fontSize: textStyle.fontsize_16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  // Handle add friend action (e.g. from user profile in group/contact)
  Future<void> _onAddFriend(BuildContext context, String userID) async {
    final requestMessage = AppLocalizations.of(context)?.defaultFriendRequestMessage ?? 'Hello';
    try {
      await widget.service.addFriend(userID, requestMessage: requestMessage);
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.friendRequestSent)),
        );
        // Refresh contacts to update UI
        FakeUIKit.instance.im?.refreshContacts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedToSendFriendRequest(e.toString()))),
        );
      }
    }
  }

  Future<void> _loadBootstrapServiceStatus() async {
    if (!mounted) return;
    
    final running = await Prefs.getLanBootstrapServiceRunning();
    if (running) {
      final info = await LanBootstrapServiceManager.instance.getBootstrapServiceInfo();
      if (mounted) {
        setState(() {
          _lanBootstrapServiceRunning = running;
          if (info != null) {
            _lanBootstrapServiceIP = info.ip;
            _lanBootstrapServicePort = info.port;
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _lanBootstrapServiceRunning = false;
          _lanBootstrapServiceIP = null;
          _lanBootstrapServicePort = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Save tox profile when app goes to background to reduce data loss on kill/crash
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.service.saveToxProfileNow();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      super.dispose();
      return;
    }
    _disposed = true;

    _refreshTimer?.cancel();
    _refreshTimer = null;

    _bootstrapServiceStatusTimer?.cancel();
    _bootstrapServiceStatusTimer = null;

    _msgSub?.cancel();
    _msgSub = null;

    _progressUpdatesSub?.cancel();
    _progressUpdatesSub = null;

    _connectionStatusSub?.cancel();
    _connectionStatusSub = null;

    _conversationDataSub?.cancel();
    _conversationDataSub = null;

    _contactDataSub?.cancel();
    _contactDataSub = null;

    _groupProfileDataSub?.cancel();
    _groupProfileDataSub = null;

    _friendsSub?.cancel();
    _friendsSub = null;

    _appsSub?.cancel();
    _appsSub = null;

    _bag.dispose();
    super.dispose();
  }

  Future<void> _loadLocalFriends() async {
    final friends = await Prefs.getLocalFriends();
    if (!mounted) return;
    setState(() {
      _localFriends = friends;
    });
  }

  Future<void> _load() async {
    final list = await widget.service.getFriendList();
    if (!mounted) return;
    // Always reload from Prefs to get the latest state (important after friend deletion)
    // Add a small delay to ensure SharedPreferences writes have completed
    await Future.delayed(const Duration(milliseconds: 100));
    final localFriendsToUse = await Prefs.getLocalFriends();
    if (mounted) {
      setState(() {
        _localFriends = localFriendsToUse;
      });
    }
    // merge locally persisted friends (ensure existence in list)
    // Normalize friend IDs to 64 characters (Tox public key length) for comparison
    final existingIds = list.map((e) => normalizeToxId(e.userId)).toSet();
    final merged = <({String userId, String nickName, bool online, String status})>[...list];
    // Normalize all persisted friend IDs for consistent comparison
    final normalizedLocalFriends = localFriendsToUse.map((uid) => normalizeToxId(uid)).toSet();
    // Load cached nicknames for offline friends
    for (final normalizedUid in normalizedLocalFriends) {
      if (!existingIds.contains(normalizedUid)) {
        // Load nickname and status from cache for offline friends
        final cachedNick = await Prefs.getFriendNickname(normalizedUid);
        final cachedStatus = await Prefs.getFriendStatusMessage(normalizedUid);
        merged.add((
          userId: normalizedUid, 
          nickName: cachedNick ?? '', 
          online: false, 
          status: cachedStatus ?? ''
        ));
      }
    }
    setState(() {
      _friends = merged;
    });
    await _updateTray();
  }

  /// Sync persisted friends to Tox: re-add friends that are in local persistence but not in Tox
  /// This ensures that friends saved in Flutter's local persistence are also added to Tox,
  /// so that Tox can send online status updates to them.
  Future<void> _syncPersistedFriendsToTox() async {
    try {
      // Get persisted friends from local storage
      final persistedFriends = await Prefs.getLocalFriends();
      if (persistedFriends.isEmpty) {
        return;
      }
      
      // Get current Tox friend list
      final toxFriends = await widget.service.getFriendList();
      final toxFriendIds = toxFriends.map((f) {
        final id = f.userId.trim();
        return id.length > 64 ? id.substring(0, 64) : id;
      }).toSet();
      
      
      // Find friends that are in persistence but not in Tox
      final friendsToReAdd = <String>[];
      for (final persistedId in persistedFriends) {
        final normalizedId = persistedId.trim();
        final actualId = normalizedId.length > 64 ? normalizedId.substring(0, 64) : normalizedId;
        if (!toxFriendIds.contains(actualId)) {
          friendsToReAdd.add(actualId);
        }
      }
      
      if (friendsToReAdd.isEmpty) {
        return;
      }
      
      
      // Re-add missing friends to Tox using acceptFriendRequest (which uses tox_friend_add_norequest)
      // This will add them to Tox's friend list, allowing Tox to send online status updates
      for (final friendId in friendsToReAdd) {
        try {
          await widget.service.acceptFriendRequest(friendId);
          // Wait a bit between adds to avoid overwhelming Tox
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
        }
      }
      
    } catch (e) {
    }
  }

  void _openChat({String? peerId, String? groupId}) {
    setState(() {
      _index = 0; // Ensure Chats tab is visible
    });
    _selectConversation(peerId: peerId, groupId: groupId);
    unawaited(_updateTray());
  }

  Future<void> _sendMedia(BuildContext context, {String? userId, String? groupId, required _MediaPickType type}) async {
    final appL10n = AppLocalizations.of(context)!;
    final label = type == _MediaPickType.image ? appL10n.photo : appL10n.video;
    if (groupId != null && groupId.isNotEmpty) {
      _showSnackBar(appL10n.sendingToGroupsNotSupported(label));
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type == _MediaPickType.image ? FileType.image : FileType.video,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        _showSnackBar(appL10n.noLabelSelected(label));
        return;
      }
      if (userId != null) {
        // Check if friend is online before sending
        final friends = await widget.service.getFriendList();
        final friend = friends.firstWhere(
          (f) => f.userId == userId,
          orElse: () => (userId: userId, nickName: '', online: false, status: ''),
        );
        if (!friend.online) {
          // Send a text message to chat window indicating failure (two lines: error + file path)
          final failureMsg = type == _MediaPickType.image 
              ? appL10n.friendOfflineSendImageFailed 
              : appL10n.friendOfflineSendVideoFailed;
          final twoLineMsg = '$failureMsg\n$path';
          final mgr = FakeUIKit.instance.messageManager;
          if (mgr != null) {
            await mgr.sendText('c2c_$userId', twoLineMsg);
          }
          return;
        }
        await widget.service.sendFile(userId, path);
        _showSnackBar('$label sent');
      }
    } catch (e) {
      final appL10n = AppLocalizations.of(context)!;
      final errorMsg = e.toString();
      String userMsg;
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Send a text message to chat window indicating failure (two lines: error + file path)
        // Note: path variable is not available in catch block, so we skip file path in error message
        if (userId != null) {
          final failureMsg = type == _MediaPickType.image 
              ? appL10n.friendOfflineSendImageFailed 
              : appL10n.friendOfflineSendVideoFailed;
          final mgr = FakeUIKit.instance.messageManager;
          if (mgr != null) {
            await mgr.sendText('c2c_$userId', failureMsg);
          }
        }
        userMsg = appL10n.friendOfflineCannotSendFile;
      } else {
        // Extract error message without file path
        String errorText = e.toString();
        final appL10n = AppLocalizations.of(context)!;
        // Remove file path from error message if present
        if (errorText.contains('File does not exist')) {
          errorText = appL10n.fileDoesNotExist;
        } else if (errorText.contains('File is empty')) {
          errorText = appL10n.fileIsEmpty;
        } else if (errorText.contains(':')) {
          // Remove path after colon (e.g., "Exception: /path/to/file")
          final colonIndex = errorText.indexOf(':');
          if (colonIndex > 0) {
            final beforeColon = errorText.substring(0, colonIndex);
            final afterColon = errorText.substring(colonIndex + 1).trim();
            // Check if after colon looks like a file path
            if (afterColon.startsWith('/') || afterColon.contains('\\')) {
              errorText = beforeColon;
            }
          }
        }
        userMsg = appL10n.failedToSendFile(label, errorText);
      }
      _showSnackBar(userMsg);
    }
  }

  Future<String> _createSelfQrCardImage() async {
    final nick = await Prefs.getNickname();
    final avatarPath = await Prefs.getAvatarPath();
    final displayName = (nick != null && nick.trim().isNotEmpty) ? nick.trim() : widget.service.selfId;
    final locale = AppLocale.locale.value;
    final appL10n = AppLocalizations.of(context);
    return generateContactCardImage(
      userId: widget.service.selfId,
      displayName: displayName,
      locale: locale,
      bottomText: appL10n?.scanQrCodeToAddContact ?? 'Scan QR code to add me as contact',
      primaryColor: AppThemeConfig.primaryColor,
      avatarPath: avatarPath,
    );
  }

  List<TencentCloudChatMessageGeneralOptionItem> _buildDesktopInputOptions(BuildContext context, {String? userID, String? groupID}) {
    final appL10n = AppLocalizations.of(context)!;
    final photoLabel = appL10n.photo;
    final videoLabel = appL10n.video;
    final personalCardLabel = appL10n.personalCard;
    final personalCardGroupLabel = appL10n.sendPersonalCardToGroup;
    final sentSnack = appL10n.personalCardSent;
    final sentGroupSnack = appL10n.sentPersonalCardToGroup;
    final options = <TencentCloudChatMessageGeneralOptionItem>[
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.photo_outlined,
        label: photoLabel,
        onTap: ({Offset? offset}) async {
          await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.image);
        },
      ),
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.videocam_outlined,
        label: videoLabel,
        onTap: ({Offset? offset}) async {
          await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.video);
        },
      ),
    ];
    if (userID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code_2,
          label: personalCardLabel,
          onTap: ({Offset? offset}) async {
            try {
              // Check if friend is online before sending
              final friends = await widget.service.getFriendList();
              final friend = friends.firstWhere(
                (f) => f.userId == userID,
                orElse: () => (userId: userID, nickName: '', online: false, status: ''),
              );
              if (!friend.online) {
                final appL10n = AppLocalizations.of(context)!;
                // Send a text message to chat window indicating failure (two lines: error + file path)
                final qrPath = await _createSelfQrCardImage();
                final twoLineMsg = '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                final mgr = FakeUIKit.instance.messageManager;
                if (mgr != null) {
                  await mgr.sendText('c2c_$userID', twoLineMsg);
                }
                return;
              }
              final qrPath = await _createSelfQrCardImage();
              await widget.service.sendFile(userID, qrPath);
              _showSnackBar(sentSnack);
            } catch (e, stackTrace) {
              // Provide more user-friendly error messages
              final appL10n = AppLocalizations.of(context)!;
              final errorMsg = e.toString();
              String userMsg;
              if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
                // Send a text message to chat window indicating failure (two lines: error + file path)
                // Try to get the file path from the error or use a default message
                try {
                  final qrPath = await _createSelfQrCardImage();
                  final twoLineMsg = '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                  final mgr = FakeUIKit.instance.messageManager;
                  if (mgr != null) {
                    await mgr.sendText('c2c_$userID', twoLineMsg);
                  }
                } catch (e, st) {
                  AppLogger.logError(
                    '[HomePage] Failed to create self QR card image for offline fallback',
                    e,
                    st,
                  );
                  final mgr = FakeUIKit.instance.messageManager;
                  if (mgr != null) {
                    await mgr.sendText('c2c_$userID', appL10n.friendOfflineSendCardFailed);
                  }
                }
                userMsg = appL10n.friendOfflineCannotSendFile;
              } else if (errorMsg.contains('not in your friend list')) {
                userMsg = appL10n.userNotInFriendList;
              } else {
                // Extract error message without file path
                String errorText = e.toString();
                final appL10n = AppLocalizations.of(context)!;
                // Remove file path from error message if present
                if (errorText.contains('File does not exist')) {
                  errorText = appL10n.fileDoesNotExist;
                } else if (errorText.contains('File is empty')) {
                  errorText = appL10n.fileIsEmpty;
                } else if (errorText.contains(':')) {
                  // Remove path after colon (e.g., "Exception: /path/to/file")
                  final colonIndex = errorText.indexOf(':');
                  if (colonIndex > 0) {
                    final beforeColon = errorText.substring(0, colonIndex);
                    final afterColon = errorText.substring(colonIndex + 1).trim();
                    // Check if after colon looks like a file path
                    if (afterColon.startsWith('/') || afterColon.contains('\\')) {
                      errorText = beforeColon;
                    }
                  }
                }
                userMsg = appL10n.sendFailed(errorText);
              }
              _showSnackBar(userMsg);
            }
          },
        ),
      );
    } else if (groupID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code,
          label: personalCardGroupLabel,
          onTap: ({Offset? offset}) async {
            final appL10n = AppLocalizations.of(context)!;
            final text = '${appL10n.myId}: ${widget.service.selfId}';
            await widget.service.sendGroupText(groupID, text);
            _showSnackBar(sentGroupSnack);
          },
        ),
      );
    }
    return options;
  }

  Future<void> _updateTray() async {
    if (!AppTray.instance.isSupported) return;
    // Get total unread count from UIKit (includes all conversations and groups)
    final uikitUnreadCount = TencentCloudChat.instance.dataInstance.conversation.totalUnreadCount;
    // Get friend application unread count
    final applicationUnreadCount = TencentCloudChat.instance.dataInstance.contact.applicationUnreadCount;
    // Total count = conversation unread + friend applications
    final totalCount = uikitUnreadCount + applicationUnreadCount;
    await AppTray.instance.update(count: totalCount, online: widget.service.isConnected);
  }

  @override
  Widget build(BuildContext context) {
    // Keep UIKit intl in sync with app locale
    try {
      TencentCloudChatIntl().init(context);
      // Also force set to current app locale to update caches immediately
      // Delay setLocale to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          TencentCloudChatIntl().setLocale(AppLocale.locale.value);
        } catch (e, st) {
          AppLogger.logError('[HomePage] Failed to update chat locale', e, st);
        }
      });
    } catch (e, st) {
      AppLogger.logError('[HomePage] Global adapter init failed', e, st);
    }
    if (!_globalAdapterInited) {
      try {
        // Set contact event handlers for navigation
        // Note: onNavigateToChat is an alias for onTapContactItem (getter that returns _onTapContactItem)
        TencentCloudChat.instance.dataInstance.contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
          uiEventHandlers: TencentCloudChatContactUIEventHandlers(
            onTapContactItem: ({String? userID, String? groupID}) async {
              // Handle navigation from contact list and profile page "Send Message" button
              if (userID != null) {
                // Check if we're already in a profile page (Navigator can pop)
                // If yes, this is a "Send Message" click, so navigate to chat
                // If no, this is a contact list click, so show profile
                final canPop = Navigator.of(context).canPop();
                if (canPop) {
                  // We're in a profile page, close it and navigate to chat
                  Navigator.of(context).pop();
                  // Switch to chats tab and open 1:1 chat
                  setState(() {
                    _index = 0;
                  });
                  _selectConversation(peerId: userID);
                  return true; // Handled, prevent default navigation
                } else {
                  // We're in contact list, show profile page on the right side
                  _showUserProfileOnRight(context, userID);
                  return true; // Handled, prevent default navigation
                }
              } else if (groupID != null) {
                // For groups, still switch to chats tab and open group chat
                setState(() {
                  _index = 0;
                });
                _selectConversation(groupId: groupID);
                return true; // Handled, prevent default navigation
              }
              return false;
            },
          ),
        );
        
        TencentCloudChat.controller.initGlobalAdapterInBuildPhase(context);
        _globalAdapterInited = true;
      } catch (e) {
      }
    }
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return Builder(
          builder: (scaffoldCtx) {
            _scaffoldMessengerContext = scaffoldCtx;
            final isMobile = ResponsiveLayout.isMobile(context);
            final isTablet = ResponsiveLayout.isTablet(context);
            final isDesktop = ResponsiveLayout.isDesktop(context);
            
            Widget content = PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                // If not on the Chats tab, go back to Chats
                if (_index != 0) {
                  setState(() { _index = 0; });
                  return;
                }
                // On Chats tab: double-press back to exit
                final now = DateTime.now();
                if (_lastBackPressTime != null &&
                    now.difference(_lastBackPressTime!) < const Duration(seconds: 2)) {
                  SystemNavigator.pop();
                  return;
                }
                _lastBackPressTime = now;
                AppSnackBar.show(_scaffoldMessengerContext ?? context, AppLocalizations.of(context)!.pressBackAgainToExit);
              },
              child: Scaffold(
              drawer: isMobile ? _buildMobileDrawer() : null,
              body: SafeArea(
                child: Stack(
                children: [
                  Row(
                    children: [
                      if (!isMobile) ...[
                        SizedBox(
                          width: ResponsiveLayout.responsiveSidebarWidth(context),
                          child: _uikitSidebar(),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: [
                        ValueListenableBuilder<Locale>(
                          valueListenable: AppLocale.locale,
                          builder: (context, locale, _) {
                            // Delay setLocale to avoid calling setState during build
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              try {
                                TencentCloudChatIntl().setLocale(locale);
                              } catch (_) {}
                            });
                            return TencentCloudChatConversation(
                              key: ValueKey('uikit-conversation-${locale.languageCode}'),
                            );
                          },
                        ),
                        ValueListenableBuilder<Locale>(
                          valueListenable: AppLocale.locale,
                          builder: (context, locale, _) {
                            // Delay setLocale to avoid calling setState during build
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              try {
                                TencentCloudChatIntl().setLocale(locale);
                              } catch (_) {}
                            });
                            return ValueListenableBuilder<ThemeMode>(
                              valueListenable: AppTheme.mode,
                              builder: (context, themeMode, __) {
                                return Stack(
                                  children: [
                                    TencentCloudChatThemeWidget(
                                      build: (context, themeColors, textStyles) {
                                        return TencentCloudChatContact(
                                          key: ValueKey('uikit-contact-${locale.languageCode}-${themeMode.name}'),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 16,
                                      right: 24,
                                      child: NewEntryButton(
                                        onAddFriend: _showAddFriendDialog,
                                        onCreateGroup: _showAddGroupDialog,
                                        onJoinIrcChannel: _ircAppInstalled ? _showJoinIrcChannelDialog : null,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        ApplicationsPage(service: widget.service),
                        SettingsPage(
                          service: widget.service,
                          connectionStatusStream: widget.service.connectionStatusStream,
                          autoAcceptFriends: _autoAcceptFriends,
                          onAutoAcceptFriendsChanged: _setAutoAcceptFriends,
                          autoAcceptGroupInvites: _autoAcceptGroupInvites,
                          onAutoAcceptGroupInvitesChanged: _setAutoAcceptGroupInvites,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                  // Bootstrap service status banner (desktop only)
                  if (PlatformUtils.isDesktop)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 300),
                        offset: (_lanBootstrapServiceRunning && _lanBootstrapServiceIP != null && _lanBootstrapServicePort != null)
                            ? Offset.zero
                            : const Offset(0, -1),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: (_lanBootstrapServiceRunning && _lanBootstrapServiceIP != null && _lanBootstrapServicePort != null)
                              ? 1.0
                              : 0.0,
                          child: Material(
                            elevation: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: colorTheme.secondButtonColor.withValues(alpha: 0.1),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_done,
                                    color: colorTheme.secondButtonColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (_lanBootstrapServiceIP != null && _lanBootstrapServicePort != null)
                                          ? AppLocalizations.of(context)!.bootstrapServiceRunning(
                                              _lanBootstrapServiceIP!,
                                              _lanBootstrapServicePort!,
                                            )
                                          : '',
                                      style: TextStyle(
                                        color: colorTheme.primaryTextColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _lanBootstrapServiceRunning = false;
                                      });
                                    },
                                    tooltip: AppLocalizations.of(context)!.hide,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              ),
              bottomNavigationBar: isMobile ? _buildBottomNavigationBar() : null,
            ),
            );
            return content;
          },
        );
      },
    );
  }

  Widget? _buildMobileDrawer() {
    return Drawer(
      width: 280,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: buildSidebar(
          context: context,
          selectedIndex: _index,
          onTap: (i) {
            setState(() {
              _index = i;
            });
            Navigator.of(context).pop(); // Close drawer
            // Refresh IRC app status when switching to Applications page
            if (i == 2) {
              _checkIrcAppStatus();
            }
          },
          service: widget.service,
          connectionStatusStream: widget.service.connectionStatusStream,
        ),
      ),
    );
  }

  Widget? _buildBottomNavigationBar() {
    final l10n = AppLocalizations.of(context)!;
    return BottomNavigationBar(
      currentIndex: _index,
      onTap: (i) {
        setState(() {
          _index = i;
        });
        // Refresh IRC app status when switching to Applications page
        if (i == 2) {
          _checkIrcAppStatus();
        }
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      items: [
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.chat),
              Positioned(
                top: -5,
                right: -6,
                child: UnconstrainedBox(
                  child: TencentCloudChatConversationTotalUnreadCount(
                    builder: (BuildContext _, int totalUnreadCount) {
                      if (totalUnreadCount == 0) {
                        return Container();
                      }
                      final displayText = totalUnreadCount > 99 ? "99+" : "$totalUnreadCount";
                      final isLargeText = displayText.length > 2;
                      return UnconstrainedBox(
                        child: Container(
                          width: isLargeText ? 26 : (displayText.length == 1 ? 16 : 20),
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: isLargeText ? BoxShape.rectangle : BoxShape.circle,
                            borderRadius: isLargeText ? BorderRadius.circular(AppThemeConfig.badgeBorderRadius) : null,
                          ),
                          child: Center(
                            child: Text(
                              displayText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          label: l10n.chats,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.contacts),
          label: l10n.contacts,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.apps),
          label: l10n.applications,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.settings),
          label: l10n.settings,
        ),
      ],
    );
  }

  Widget _uikitSidebar() {
    return buildSidebar(
      context: context,
      selectedIndex: _index,
      onTap: (i) {
        setState(() {
          _index = i;
        });
        // Refresh IRC app status when switching to Applications page
        if (i == 2) {
          _checkIrcAppStatus();
        }
      },
      service: widget.service,
      connectionStatusStream: widget.service.connectionStatusStream,
    );
  }

  /// Show user profile page - uses router which handles desktop/mobile modes
  void _showUserProfileOnRight(BuildContext context, String userID) {
    TencentCloudChatRouter().navigateTo(
      context: context,
      routeName: TencentCloudChatRouteNames.userProfile,
      options: TencentCloudChatUserProfileOptions(userID: userID),
    );
  }

  void _selectConversation({String? peerId, String? groupId}) {
    final convData = TencentCloudChat.instance.dataInstance.conversation;
    final bool hasPeer = peerId != null && peerId.isNotEmpty;
    final bool hasGroup = groupId != null && groupId.isNotEmpty;
    if (!hasPeer && !hasGroup) {
      widget.service.setActivePeer(null);
      return;
    }
    final String targetConvId = hasGroup ? 'group_$groupId' : 'c2c_${peerId!}';

    V2TimConversation? target;
    for (final conv in convData.conversationList) {
      if (conv.conversationID == targetConvId) {
        target = conv;
        break;
      }
    }
    if (target == null) {
      target = V2TimConversation(
        conversationID: targetConvId,
        type: hasGroup ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C,
        userID: hasGroup ? null : peerId,
        groupID: hasGroup ? groupId : null,
        showName: hasGroup ? groupId : peerId,
        unreadCount: 0,
      );
    }
    convData.currentConversation = target;
  }

  Future<void> _setAutoAcceptFriends(bool value) async {
    if (_autoAcceptFriends == value) return;
    setState(() => _autoAcceptFriends = value);
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptFriends(value, toxId);
    }
    if (value && _pendingFriendApps.isNotEmpty) {
      await _acceptFriendApplications(List<V2TimFriendApplication>.from(_pendingFriendApps));
    }
  }

  Future<void> _setAutoAcceptGroupInvites(bool value) async {
    if (_autoAcceptGroupInvites == value) return;
    setState(() => _autoAcceptGroupInvites = value);
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptGroupInvites(value, toxId);
    }
    // Update FFI setting so C++ can read it
    widget.service.setAutoAcceptGroupInvites(value);
  }

  Future<void> _acceptFriendApplications(List<V2TimFriendApplication> apps) async {
    for (final app in apps) {
      final uid = app.userID;
      if (uid.isEmpty) continue;
      try {
        await widget.service.acceptFriendRequest(uid);
      } catch (e) {
      }
    }
    _pendingFriendApps = [];
    if (mounted) setState(() {});
    await FakeUIKit.instance.im?.refreshContacts();
    await _load();
      _showSnackBar(AppLocalizations.of(context)!.autoAcceptedNewFriendRequest);
    await _updateTray();
  }

  Future<void> _handleFriendAdded(String friendId) async {
    final trimmed = friendId.trim();
    if (trimmed.isEmpty) return;
    // Don't write to Prefs here — FakeIM._emitContactsWithFriendsImpl is the
    // single authority for Prefs.localFriends. It will persist the Tox friend list
    // on the next refresh cycle. Writing here risks re-adding stale friends from
    // _localFriends.
    await FakeUIKit.instance.im?.refreshContacts();
    await _load();
  }

  /// Load persisted groups into UIKit on app startup
  /// This ensures groups are visible in the group list even if contacts haven't been refreshed yet
  Future<void> _loadPersistedGroupsIntoUIKit() async {
    try {
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Loading persisted groups');
      
      // Load groups directly from Prefs instead of relying on service.knownGroups
      // This ensures we get groups even if service.init() hasn't completed yet
      final savedGroups = await Prefs.getGroups();
      final quitGroups = await Prefs.getQuitGroups();
      // Only load groups that are not in quit list
      final activeGroups = savedGroups.where((g) => !quitGroups.contains(g)).toSet();
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Loaded ${activeGroups.length} groups from Prefs (savedGroups=${savedGroups.length}, quitGroups=${quitGroups.length})');
      
      // Also try to get groups from service (in case init() has completed)
      final knownGroups = widget.service.knownGroups;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: knownGroups from service: ${knownGroups.length} groups');
      
      // Merge both sources to ensure we have all groups
      final allGroups = {...activeGroups, ...knownGroups};
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Total groups to load: ${allGroups.length}');
      
      // Load group info for each group and add to UIKit
      for (final gid in allGroups) {
        final savedName = await Prefs.getGroupName(gid);
        final savedAvatar = await Prefs.getGroupAvatar(gid);
        final groupInfo = V2TimGroupInfo(
          groupID: gid,
          groupType: "work",
          groupName: savedName,
          faceUrl: savedAvatar,
        );
        // addGroupInfoToJoinedGroupList will check if group already exists and update it if needed
        TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
      }
      
      // Also call getGroupList() to refresh the list from SDK
      // However, we need to preserve existing groups because SDK may not know about historical groups
      // Save existing groups before calling getGroupList()
      final groupsBeforeSDK = List<V2TimGroupInfo>.from(TencentCloudChat.instance.dataInstance.contact.groupList);
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Groups before getGroupList(): ${groupsBeforeSDK.length}, groupIds=${groupsBeforeSDK.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      await TencentCloudChat.instance.chatSDKInstance.contactSDK.getGroupList();
      
      final sdkGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: SDK returned ${sdkGroupList.length} groups: ${sdkGroupList.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Use quitGroups that was already loaded earlier (line 1836)
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Quit groups: ${quitGroups.toList()}');
      
      // Merge SDK groups with existing groups to preserve historical groups.
      // When our source of truth (Prefs + service) has no groups (e.g. new account after logout),
      // do not merge in groupsBeforeSDK — they are stale from the previous account.
      final groupsMap = <String, V2TimGroupInfo>{};
      if (allGroups.isNotEmpty) {
        // First add existing groups from UIKit (filter out quit groups and empty groupIDs)
        for (final group in groupsBeforeSDK) {
          if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
          if (!quitGroups.contains(group.groupID)) {
            groupsMap[group.groupID] = group;
          } else {
            if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Filtering out quit group: ${group.groupID}');
          }
        }
      }
      // Then add/update with SDK groups (SDK groups take precedence, but filter out quit groups and empty groupIDs)
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        if (!quitGroups.contains(group.groupID)) {
          groupsMap[group.groupID] = group;
        } else {
          if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Filtering out quit group from SDK list: ${group.groupID}');
        }
      }

      final mergedGroups = groupsMap.values.toList();
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Merged ${mergedGroups.length} groups: ${mergedGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Update with merged groups
      TencentCloudChat.instance.dataInstance.contact.buildGroupList(mergedGroups, '_loadPersistedGroupsIntoUIKit_merge');
      
      final finalGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Final groupList length=${finalGroupList.length}, groupIds=${finalGroupList.map((g) => g.groupID).toList()}');
      
      // Refresh conversations to ensure conversation list is in sync with group list
      // This is critical for startup scenario to ensure data consistency
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Refreshing conversations to sync with group list');
      await FakeUIKit.instance.im?.refreshConversations();
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] _loadPersistedGroupsIntoUIKit: Error loading groups', e, stackTrace);
    }
  }

  Future<void> _handleGroupChanged(String groupId, {String? displayName}) async {
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: groupId=$groupId, displayName=$displayName');
    if (displayName != null && displayName.isNotEmpty) {
      await Prefs.setGroupName(groupId, displayName);
    }
    
    // Clear UIKit's in-memory message list for this group ID.
    // When a group ID is reused (e.g., quit tox_7 then create new tox_7),
    // UIKit's _messageListMap may still hold old messages from the previous group.
    TencentCloudChat.instance.dataInstance.messageData.clearMessageList(groupID: groupId);

    // CRITICAL: Save existing groups before calling getGroupList()
    // This is necessary because buildGroupList() clears the entire list and only keeps SDK-returned groups
    // SDK may not know about historical groups, so we need to preserve them
    final existingGroups = List<V2TimGroupInfo>.from(TencentCloudChat.instance.dataInstance.contact.groupList);
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Saved ${existingGroups.length} existing groups before getGroupList: ${existingGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');

    // Delete old group info from UIKit first to ensure clean state
    // This is important when group ID is reused (e.g., numeric IDs)
    TencentCloudChat.instance.dataInstance.contact.deleteGroupInfoFromJoinedGroupList(groupId);
    
    // Refresh group list in UIKit first to ensure we have the latest list from SDK
    // However, we need to merge SDK groups with existing groups to preserve historical groups
    try {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Calling getGroupList()');
      await TencentCloudChat.instance.chatSDKInstance.contactSDK.getGroupList();
      final sdkGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: After getGroupList(), SDK returned ${sdkGroupList.length} groups: ${sdkGroupList.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Merge SDK groups with existing groups (excluding the group being updated)
      // This preserves historical groups that SDK doesn't know about
      final existingGroupsMap = <String, V2TimGroupInfo>{};
      for (final group in existingGroups) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        if (group.groupID != groupId) { // Exclude the group being updated
          existingGroupsMap[group.groupID] = group;
        }
      }

      // Add SDK groups to the map (they will override existing groups with same ID)
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        existingGroupsMap[group.groupID] = group;
      }
      
      // Rebuild the merged list
      final mergedGroups = existingGroupsMap.values.toList();
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Merged ${mergedGroups.length} groups (${existingGroups.length} existing + ${sdkGroupList.length} SDK): ${mergedGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Update the group list with merged groups
      TencentCloudChat.instance.dataInstance.contact.buildGroupList(mergedGroups, '_handleGroupChanged_merge');
    } catch (e) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: getGroupList() failed: $e');
    }
    // Update group info in UIKit to ensure it has the latest data (including cleared avatar)
    // This is called after getGroupList() to ensure the new group is added even if getGroupList
    // didn't include it (e.g., due to timing issues)
    final savedName = await Prefs.getGroupName(groupId);
    final savedAvatar = await Prefs.getGroupAvatar(groupId);
    final groupInfo = V2TimGroupInfo(
      groupID: groupId,
      groupType: "work",
      groupName: savedName,
      faceUrl: savedAvatar, // This will be null if cleared, ensuring UIKit doesn't use old avatar
    );
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Adding groupInfo: groupID=${groupInfo.groupID}, groupName=${groupInfo.groupName}');
    TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
    final afterAddGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: After addGroupInfoToJoinedGroupList(), groupList length=${afterAddGroupList.length}, groupIds=${afterAddGroupList.map((g) => g.groupID).toList()}');
    
    // Ensure group is in knownGroups and persisted before refreshing conversations
    // This ensures refreshConversations() can find the new group
    if (!widget.service.knownGroups.contains(groupId)) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Group $groupId not in knownGroups, ensuring it is added');
      // The group should already be in knownGroups from createGroup, but double-check
      // If not, we need to ensure it's added (though this shouldn't happen)
    }
    
    // Ensure group is persisted to Prefs before refreshing conversations
    final currentPersistedGroups = await Prefs.getGroups();
    if (!currentPersistedGroups.contains(groupId)) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Group $groupId not in persisted groups, adding it');
      currentPersistedGroups.add(groupId);
      await Prefs.setGroups(currentPersistedGroups);
    }
    
    // Small delay to ensure persistence is complete
    await Future.delayed(const Duration(milliseconds: 50));

    // CRITICAL: Unblock the conversation in FakeChatDataProvider.
    // deleteGroupInfoFromJoinedGroupList (above) fires a quitGroup event which adds
    // this conversation to _sdkDeletedConvIds, preventing it from being rebuilt with
    // proper showName. Remove it so refreshConversations can re-create it correctly.
    final provider = ChatDataProviderRegistry.provider;
    if (provider is FakeChatDataProvider) {
      provider.unblockConversation('group_$groupId');
    }

    // Refresh conversations to update conversation list
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Refreshing conversations to add group $groupId to conversation list');
    await FakeUIKit.instance.im?.refreshConversations();
    await _updateTray();
  }

  Future<void> _showAddFriendDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: AddFriendDialog(
          service: widget.service,
          onFriendAdded: (id) async {
            await _handleFriendAdded(id);
          },
          onShowSnackBar: _showSnackBar,
        ),
      ),
    );
  }

  Future<void> _showAddGroupDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: AddGroupDialog(
          service: widget.service,
          onGroupChanged: (gid, {String? displayName}) async {
            await _handleGroupChanged(gid, displayName: displayName);
          },
          onShowSnackBar: _showSnackBar,
        ),
      ),
    );
  }

  Future<void> _checkIrcAppStatus() async {
    final ircAppManager = IrcAppManager();
    await ircAppManager.init();
    if (mounted) {
      setState(() {
        _ircAppInstalled = ircAppManager.isInstalled;
      });
    }
  }

  Future<void> _showJoinIrcChannelDialog() async {
    final ircAppManager = IrcAppManager();
    await ircAppManager.init();
    
    // Check if app is installed
    if (!ircAppManager.isInstalled) {
      final appL10n = AppLocalizations.of(context)!;
      _showSnackBar(appL10n.ircAppNotInstalled);
      return;
    }

    final result = await showDialog<({String channel, String? password})>(
      context: context,
      builder: (ctx) => const IrcChannelDialog(),
    );

    if (result == null || result.channel.isEmpty) return;

    try {
      final groupId = await ircAppManager.addChannel(
        result.channel,
        widget.service,
        password: result.password,
      );
      if (groupId != null) {
        await _handleGroupChanged(groupId, displayName: 'IRC: ${result.channel}');
        final appL10n = AppLocalizations.of(context)!;
        _showSnackBar(appL10n.ircChannelAdded(result.channel));
      } else {
        final appL10n = AppLocalizations.of(context)!;
        _showSnackBar(appL10n.ircChannelAddFailed);
      }
    } catch (e) {
      final appL10n = AppLocalizations.of(context);
      _showSnackBar('${appL10n?.failed ?? 'Failed'}: $e');
    }
  }

  void _showSnackBar(String message) {
    final ctx = _scaffoldMessengerContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showMessageReceiversDialog(BuildContext context, String msgID, String groupID) async {
    final manager = FakeUIKit.instance.messageManager;
    if (manager == null) return;
    
    final receivers = manager.getMessageReceivers(msgID);
    if (receivers.isEmpty) {
      _showSnackBar(AppLocalizations.of(context)!.noReceivers);
      return;
    }
    
    // Get friend list to get nicknames
    final friends = await widget.service.getFriendList();
    final friendMap = {for (var f in friends) f.userId: f.nickName};
    
    // Show dialog with receiver list
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.messageReceivers(receivers.length.toString())),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: receivers.length,
            itemBuilder: (context, index) {
              final userId = receivers[index];
              final nickname = friendMap[userId] ?? userId;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(nickname.isNotEmpty ? nickname.substring(0, 1).toUpperCase() : '?'),
                ),
                title: Text(nickname.isNotEmpty ? nickname : userId),
                subtitle: Text(
                  userId,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }
}
