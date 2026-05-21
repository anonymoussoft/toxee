import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
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
import '../sdk_fake/uikit_data_facade.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import '../sdk_fake/fake_msg_provider.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
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
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import '../i18n/app_localizations.dart';
import '../util/logger.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/special_case/tencent_cloud_chat_message_no_chat.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header.dart' as msg_header;
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart' as tcc_utils;
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/data/group_profile/tencent_cloud_chat_group_profile_data.dart';
import 'group/group_builder_override.dart';
import 'group/group_member_list_wrapper.dart';
import 'package:tencent_cloud_chat_common/eventbus/tencent_cloud_chat_eventbus.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_router.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_init_data.dart';
import 'package:tencent_cloud_chat_text_translate/tencent_cloud_chat_text_translate.dart';
import 'package:tencent_cloud_chat_sound_to_text/tencent_cloud_chat_sound_to_text.dart';
import 'search/custom_search.dart' as search_pkg;
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'settings/settings_page.dart';
import 'settings/sidebar.dart';
import 'applications/applications_page.dart';
import 'home/home_utils.dart';
import 'home/toxee_message_header_info.dart';
import '../util/app_theme_config.dart';
import '../util/app_tray.dart';
import '../util/bootstrap_nodes.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/send_failure_notifier.dart';
import '../util/platform_utils.dart';
import 'add_friend_dialog.dart';
import 'add_group_dialog.dart';
import 'home/home_group_controller.dart';
import 'home/home_session_controller.dart';
import 'home/home_widgets.dart';
import '../util/irc_app_manager.dart';
import 'applications/irc_channel_dialog.dart';
import '../util/responsive_layout.dart';
import '../call/permission_helper.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'widgets/app_page_route.dart';
import 'widgets/app_snackbar.dart';
import 'package:window_manager/window_manager.dart';
import '../notifications/notification_message_listener.dart';
import '../notifications/notification_service.dart';

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
  // P1-D3: tracks which friend-request userIDs we have already fired a
  // system notification for in this session. Without this, every poll cycle
  // that re-emits the same pending application list would re-banner.
  // Cleared in dispose; survives only the in-memory session.
  final Set<String> _notifiedFriendReqUserIds = <String>{};
  bool _stickerPluginRegistered = false;
  // Set the instant we enqueue a sticker-plugin postFrame callback, so back-
  // to-back rebuilds before the callback fires don't queue duplicates.
  bool _stickerPluginRegistrationScheduled = false;
  bool _textTranslatePluginRegistered = false;
  bool _soundToTextPluginRegistered = false;
  StreamSubscription? _msgSub;
  StreamSubscription? _progressUpdatesSub;
  StreamSubscription<bool>? _connectionStatusSub;
  // P1-C3: timer that fires a banner if we stay offline 30s after a
  // disconnect (or never connect on cold start). Cancelled on
  // conn:success.
  Timer? _noConnectionBannerTimer;
  StreamSubscription<TencentCloudChatConversationData<dynamic>>? _conversationDataSub;
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  StreamSubscription<TencentCloudChatGroupProfileData<dynamic>>? _groupProfileDataSub;
  StreamSubscription<List<V2TimConversation>>? _convProviderSub;
  StreamSubscription<int>? _unreadProviderSub;
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
  bool _disposed = false;
  ContactBuilderOverrideHandle? _contactBuilderOverride;
  GroupProfileBuilderOverrideHandle? _groupBuilderOverride;
  String? _initErrorMessage;
  late final HomeSessionController _sessionController;
  late final HomeGroupController _groupController;
  // Tracks the last computed `shouldShowMasterDetail` so we only schedule the
  // UIKit `setConfigs(forceDesktopLayout: ...)` post-frame callback when the
  // breakpoint actually crosses, instead of on every rebuild.
  bool? _lastShouldShowMasterDetail;
  // True while the contact-profile route is on screen. Drives `_onTapContactItem`
  // to decide whether a contact tap means "open profile" (false) vs "Send
  // Message from inside profile" (true). Replaces the old `Navigator.canPop()`
  // heuristic which mis-fired whenever any other route (search, settings push)
  // happened to be on the stack.
  bool _inContactProfileContext = false;

  @override
  void initState() {
    super.initState();
    _sessionController = HomeSessionController(service: widget.service);
    _groupController = HomeGroupController(
      ops: GroupSyncOps.real(
        getKnownGroups: () => widget.service.knownGroups,
        onUpdateTray: _updateTray,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    _bag.add(() => WidgetsBinding.instance.removeObserver(this));
    // HYBRID MODE: Using both binary replacement (for most operations) and Platform interface (for history queries)
    // This allows:
    // - Most operations to use binary replacement (TIMManager.instance -> NativeLibraryManager -> Dart* functions)
    // - History queries to use Platform interface (Tim2ToxSdkPlatform -> FfiChatService -> MessageHistoryPersistence)
    // This ensures history messages are loaded from persistence service instead of returning empty list from C++ layer

    // Session runtime (FakeUIKit, platform, CallServiceManager) via coordinator
    unawaited(_initAfterSessionReady());
    // React to locale changes once, instead of scheduling a post-frame
    // setLocale in every `build()`. Listener fires only on value change.
    AppLocale.locale.addListener(_handleAppLocaleChanged);
    _bag.add(() => AppLocale.locale.removeListener(_handleAppLocaleChanged));
    // Register conversation secondary-tap / long-press handlers — deferred to
    // next frame so
    // UIKit's conversation event handlers singleton is wired up first (the
    // `setEventHandlers(onTapConversationItem: ...)` call lives in
    // `home_page_bootstrap.dart::_buildHomePage`, which runs during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        conv_pkg.TencentCloudChatConversationManager.eventHandlers
            .uiEventHandlers
            .setEventHandlers(
          onSecondaryTapConversationItem: ({
            required V2TimConversation conversation,
            required Offset position,
          }) async {
            if (!mounted) return false;
            await _showConversationContextMenu(conversation, position);
            return true;
          },
          onLongPressConversationItem: ({
            required V2TimConversation conversation,
            required Offset position,
          }) async {
            if (!mounted) return false;
            await _showConversationContextMenu(conversation, position);
            return true;
          },
        );
        _bag.add(() {
          // Tear down the handler closure on dispose so it can't fire
          // against a stale State context. There's no "clear" API, so set
          // it back to a no-op that returns false (default behavior).
          try {
            conv_pkg.TencentCloudChatConversationManager.eventHandlers
                .uiEventHandlers
                .setEventHandlers(
              onSecondaryTapConversationItem: ({
                required V2TimConversation conversation,
                required Offset position,
              }) async => false,
              onLongPressConversationItem: ({
                required V2TimConversation conversation,
                required Offset position,
              }) async => false,
            );
          } catch (e) {
            AppLogger.warn(
                '[HomePage] failed to restore onSecondaryTapConversationItem no-op: $e');
          }
        });
      } catch (e, st) {
        AppLogger.logError(
          '[HomePage] Failed to register conversation context-menu handlers',
          e,
          st,
        );
      }
      unawaited(_maybePrewarmCallPermissions());
    });
  }


  /// Used by home_page_bootstrap.dart extension to call setState (avoids invalid_use_of_protected_member).
  void _bootstrapSetState(VoidCallback fn) {
    setState(fn);
  }

  /// Fires when `AppLocale.locale` actually changes — pushes the new locale
  /// into UIKit's intl cache. Replaces the previous per-build post-frame
  /// scheduling pattern in `build()`.
  void _handleAppLocaleChanged() {
    if (!mounted) return;
    try {
      TencentCloudChatIntl().setLocale(AppLocale.locale.value);
    } catch (e, st) {
      AppLogger.logError('[HomePage] Failed to update chat locale', e, st);
    }
  }

  // Build "Add Friend" button widget for non-friends
  Widget _buildAddFriendButton(V2TimUserFullInfo userFullInfo) {
    return Builder(
      builder: (context) {
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              // Whole-bar hit target so the entire row is tappable (min 44pt
              // height enforced below for mobile ergonomics).
              behavior: HitTestBehavior.opaque,
              onTap: () => _onAddFriend(context, userFullInfo.userID ?? ''),
              child: Container(
                // Fill the parent — using `MediaQuery.size.width` made the
                // button stretch to the full screen even when embedded inside
                // a constrained pane (master-detail / dialog).
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1,
                      color: colorTheme.backgroundColor,
                    ),
                  ),
                  color: colorTheme.contactAddContactFriendInfoStateButtonBackgroundColor,
                ),
                // Toxee-owned widget — use literal symmetric insets rather
                // than UIKit's screen adapter so this row doesn't reach into
                // tencent_cloud_chat_common for sizing.
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                alignment: Alignment.centerLeft,
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
        AppSnackBar.show(
          context,
          AppLocalizations.of(context)!.friendRequestSent,
        );
        // Refresh contacts to update UI
        FakeUIKit.instance.im?.refreshContacts();
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.failedToSendFriendRequest(e.toString()),
        );
      }
    }
  }

  Future<void> _loadBootstrapServiceStatus() async {
    if (!mounted) return;

    final running = await Prefs.getLanBootstrapServiceRunning();
    if (running) {
      final info = await LanBootstrapServiceManager.instance.getBootstrapServiceInfo();
      if (!mounted) return;
      // Only call setState if anything actually changed — this method is
      // driven by a 2-second periodic timer; without the equality gate we
      // were forcing a full HomePage rebuild every tick.
      final newIp = info?.ip;
      final newPort = info?.port;
      if (running != _lanBootstrapServiceRunning ||
          newIp != _lanBootstrapServiceIP ||
          newPort != _lanBootstrapServicePort) {
        setState(() {
          _lanBootstrapServiceRunning = running;
          if (info != null) {
            _lanBootstrapServiceIP = info.ip;
            _lanBootstrapServicePort = info.port;
          }
        });
      }
    } else {
      if (!mounted) return;
      if (_lanBootstrapServiceRunning != false ||
          _lanBootstrapServiceIP != null ||
          _lanBootstrapServicePort != null) {
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
    // Save tox profile when the app actually goes to background. We used to
    // include `AppLifecycleState.inactive` here, but that fires for every
    // system permission popup / control-center pull / call interruption — far
    // too often for a disk write. Stick to `paused` and `detached`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.service.saveToxProfileNow();
    }
    // Best-effort resume kick: if the app thawed back to foreground and Tox is
    // still offline, re-add the currently selected bootstrap node to nudge the
    // DHT back toward a live peer set. This is intentionally conservative —
    // full mobile background reliability still needs the bigger foreground-
    // service / PushKit architecture.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBootstrapOnResume());
    }
  }

  Future<void> _maybePrewarmCallPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      final alreadyPrewarmed = await Prefs.getCallPermissionsPrewarmed();
      if (alreadyPrewarmed) return;
      await CallPermissionHelper.prewarmCallPermissions();
      await Prefs.setCallPermissionsPrewarmed(true);
    } catch (e, st) {
      AppLogger.logError(
        '[HomePage] Failed to prewarm call permissions (non-fatal)',
        e,
        st,
      );
    }
  }

  Future<void> _refreshBootstrapOnResume() async {
    try {
      if (widget.service.isConnected) return;
      final node = await Prefs.getCurrentBootstrapNode();
      if (node == null) return;
      final added = await widget.service.addBootstrapNode(
        node.host,
        node.port,
        node.pubkey,
      );
      AppLogger.debug(
        '[HomePage] resume bootstrap refresh attempted '
        '(host=${node.host}, success=$added)',
      );
    } catch (e, st) {
      AppLogger.logError(
        '[HomePage] Resume bootstrap refresh failed (non-fatal)',
        e,
        st,
      );
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

    // Defensive: _initAfterSessionReady() registers a cleanup callback on
    // `_bag` asynchronously. If dispose() races ahead of that registration,
    // DisposableBag.add() throws (it does not silently drop). Cancel the
    // timer explicitly here so the lifecycle is correct even if the bag
    // never received the cleanup callback.
    _noConnectionBannerTimer?.cancel();
    _noConnectionBannerTimer = null;

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
    final r = await _sessionController.loadContacts();
    if (!mounted) return;
    setState(() {
      _friends = r.friends;
      _localFriends = r.localFriends;
    });
    await _updateTray();
  }

  /// Sync persisted friends to Tox: re-add friends that are in local persistence but not in Tox.
  Future<void> _syncPersistedFriendsToTox() async {
    await _sessionController.syncPersistedFriendsToTox();
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
    final uikitUnreadCount = UikitDataFacade.totalUnreadCount;
    // Get friend application unread count
    final applicationUnreadCount = UikitDataFacade.applicationUnreadCount;
    // Total count = conversation unread + friend applications
    final totalCount = uikitUnreadCount + applicationUnreadCount;
    await AppTray.instance.update(count: totalCount, online: widget.service.isConnected);
  }

  @override
  Widget build(BuildContext context) {
    // Keep UIKit intl in sync with app locale. `setLocale` itself is driven
    // by `_handleAppLocaleChanged` (registered in initState) so it only fires
    // on actual locale-value changes — not every build.
    try {
      TencentCloudChatIntl().init(context);
    } catch (e, st) {
      AppLogger.logError('[HomePage] Global adapter init failed', e, st);
    }
    if (!_globalAdapterInited) {
      try {
        // Set contact event handlers for navigation
        // Note: onNavigateToChat is an alias for onTapContactItem (getter that returns _onTapContactItem)
        UikitDataFacade.contactEventHandlers = TencentCloudChatContactEventHandlers(
          uiEventHandlers: TencentCloudChatContactUIEventHandlers(
            onTapContactItem: ({String? userID, String? groupID}) async {
              // Handle navigation from contact list and profile page "Send Message" button.
              if (userID != null) {
                // Explicit state field replaces the old `Navigator.canPop()`
                // heuristic: the latter mis-fired whenever any other route
                // (search, settings push, etc.) happened to be on the stack
                // and would pop the wrong page on a contact-list tap.
                if (_inContactProfileContext) {
                  // We're inside a profile page — this is "Send Message".
                  // Close the profile, switch to chats tab, open 1:1 chat.
                  Navigator.of(context).pop();
                  setState(() {
                    _index = 0;
                    _inContactProfileContext = false;
                  });
                  _selectConversation(peerId: userID);
                  return true; // Handled, prevent default navigation
                } else {
                  // Contact list tap → show profile on the right side.
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
      } catch (e, st) {
        AppLogger.logError(
            '[HomePage] initGlobalAdapterInBuildPhase failed', e, st);
      }
    }
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return Builder(
          builder: (scaffoldCtx) {
            _scaffoldMessengerContext = scaffoldCtx;
            // `useBottomNav` is the single source of truth for "phone-y"
            // layouts (< 720pt) — replaces the old `isMobile` gate so
            // landscape phones (600-720pt) keep the bottom nav instead of
            // jumping to a sidebar. `useSidebar` is its inverse.
            final useBottomNav =
                ResponsiveLayout.shouldShowBottomNav(context);
            final useSidebar = !useBottomNav;
            final showMasterDetail =
                ResponsiveLayout.shouldShowMasterDetail(context);

            // Drive UIKit's master-detail layout from toxee's responsive
            // breakpoint. UIKit only renders desktop-mode automatically on
            // "desktop platform"; `forceDesktopLayout` lets us opt wide
            // touch devices (e.g. iPad landscape) into the same split.
            //
            // Only schedule the post-frame callback when the value actually
            // crosses the breakpoint — `build` runs on every `setState`, but
            // `setConfigs` only needs to be called on threshold transitions.
            if (showMasterDetail != _lastShouldShowMasterDetail) {
              _lastShouldShowMasterDetail = showMasterDetail;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  UikitDataFacade.setConversationConfig(
                      forceDesktopLayout: showMasterDetail);
                } catch (_) {
                  // Config object may not exist yet on the very first frame
                  // (UIKit init is async); next layout pass will pick it up.
                }
              });
            }

            // Intercept Android back only when we're truly at the root of the
            // navigator stack AND on a non-Chats tab (so back returns to
            // Chats), OR on the Chats tab with no pushed routes (so we can
            // implement double-back-to-exit). When a route is pushed (UIKit
            // chat-detail on phone, search overlay, profile page), let the
            // normal pop happen — the old unconditional `canPop: false` was
            // snapping users back to the Chats tab and breaking UIKit's
            // internal navigation stack.
            //
            // `Navigator.canPop()` is re-evaluated every `build()`; pushes
            // and pops on the root navigator trigger an ancestor rebuild
            // (`Route.didChangeNext` / `didChangePrevious`), so this value
            // stays in sync with the live stack.
            final rootNavigatorCanPop = Navigator.of(context).canPop();
            Widget content = PopScope(
              canPop: rootNavigatorCanPop,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                // At the root of the navigator stack: handle tab/exit logic.
                if (_index != 0) {
                  setState(() { _index = 0; });
                  return;
                }
                // On Chats tab at root: double-press back to exit.
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
              // Drawer removed: there was no AppBar and no `openDrawer()`
              // call site, so it was unreachable. Bottom nav covers all
              // entries on phone.
              body: SafeArea(
                child: Stack(
                children: [
                  Row(
                    children: [
                      if (useSidebar) ...[
                        SizedBox(
                          width: ResponsiveLayout.responsiveSidebarWidth(context),
                          child: Column(
                            children: [
                              // macOS traffic-light reservation — without this
                              // the avatar at the top of the sidebar sits under
                              // the window control dots.
                              if (PlatformUtils.isMacOS)
                                const SizedBox(
                                  height: ResponsiveLayout
                                      .macTitleBarReservedHeight,
                                ),
                              Expanded(child: _uikitSidebar()),
                            ],
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ],
                      Expanded(
                        child: _buildMainPane(context),
                      ),
                    ],
                  ),
                  // Bootstrap service status banner — show on native desktop
                  // and on wide tablet/desktop-class viewports (e.g. iPad in
                  // landscape) so the LAN status surface isn't hidden on
                  // bigger touch devices that can act as the LAN host.
                  if (PlatformUtils.isDesktop ||
                      ResponsiveLayout.isDesktop(context))
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      // Asymmetric enter/exit: snappy 250ms in (easeOut) so the
                      // banner shows up quickly when the LAN service comes
                      // online, faster 150ms out (easeIn) so dismissing feels
                      // responsive and doesn't linger.
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 250),
                        reverseDuration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, -1),
                            end: Offset.zero,
                          ).animate(animation);
                          return SlideTransition(
                            position: slide,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: (_lanBootstrapServiceRunning && _lanBootstrapServiceIP != null && _lanBootstrapServicePort != null)
                            ? Material(
                                key: const ValueKey('lan-bootstrap-banner'),
                                elevation: 0,
                                color: AppThemeConfig.successColor.withValues(alpha: 0.08),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: AppThemeConfig.successColor.withValues(alpha: 0.25),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.cloud_done_outlined,
                                        color: AppThemeConfig.successColor,
                                        size: 18,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          AppLocalizations.of(context)!.bootstrapServiceRunning(
                                            _lanBootstrapServiceIP!,
                                            _lanBootstrapServicePort!,
                                          ),
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        // 44x44 minimum tap area for mobile (Apple HIG / Material 48dp).
                                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
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
                              )
                            : const SizedBox.shrink(key: ValueKey('lan-bootstrap-banner-hidden')),
                      ),
                    ),
                ],
              ),
              ),
              bottomNavigationBar: useBottomNav ? _buildBottomNavigationBar() : null,
            ),
            );
            // Desktop keyboard shortcuts — meta+/ctrl+ comma/N/W/F.
            // Setting both `meta` and `control` on the SingleActivator
            // works for macOS and Win/Linux without a per-platform branch.
            if (PlatformUtils.isDesktop) {
              content = Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.comma,
                      meta: true, control: true): _OpenSettingsIntent(),
                  SingleActivator(LogicalKeyboardKey.keyN,
                      meta: true, control: true): _NewConversationIntent(),
                  SingleActivator(LogicalKeyboardKey.keyW,
                      meta: true, control: true): _CloseWindowIntent(),
                  SingleActivator(LogicalKeyboardKey.keyF,
                      meta: true, control: true): _OpenSearchIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
                      onInvoke: (_) {
                        setState(() => _index = 3);
                        return null;
                      },
                    ),
                    _NewConversationIntent:
                        CallbackAction<_NewConversationIntent>(
                      onInvoke: (_) {
                        unawaited(_showAddFriendDialog());
                        return null;
                      },
                    ),
                    _CloseWindowIntent: CallbackAction<_CloseWindowIntent>(
                      onInvoke: (_) {
                        if (PlatformUtils.isDesktop) {
                          unawaited(windowManager.close());
                        }
                        return null;
                      },
                    ),
                    _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
                      onInvoke: (_) {
                        // Cmd/Ctrl+F → push toxee's global search overlay.
                        // `userID`/`groupID` left null so the overlay runs in
                        // global mode (search all conversations).
                        final rootCtx = _scaffoldMessengerContext ?? context;
                        Navigator.of(rootCtx).push(
                          AppPageRoute(
                            page: Builder(
                              builder: (innerCtx) => search_pkg.CustomSearch(
                                closeFunc: () => Navigator.of(innerCtx).pop(),
                              ),
                            ),
                          ),
                        );
                        return null;
                      },
                    ),
                  },
                  child: Focus(autofocus: true, child: content),
                ),
              );
            }
            return content;
          },
        );
      },
    );
  }

  Widget? _buildBottomNavigationBar() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) {
            if (i == _index) {
              // Re-tap on the active tab — iOS/Android convention: scroll
              // the active list back to the top. UIKit exposes the
              // conversation list scroll controller via the controller
              // singleton; other tabs (contacts/applications/settings) don't
              // expose theirs yet — leave them as TODO.
              if (i == 0) {
                unawaited(
                  TencentCloudChatConversationController.instance
                      .scrollToTop(),
                );
              }
              // TODO: scroll-to-top for tabs 1 (contacts), 2 (applications),
              // 3 (settings) — needs controller hooks from those widgets.
              return;
            }
            setState(() {
              _index = i;
            });
            // Refresh IRC app status when switching to Applications page
            if (i == 2) {
              _checkIrcAppStatus();
            }
          },
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedItemColor: scheme.primary,
          unselectedItemColor: scheme.onSurfaceVariant,
          backgroundColor: theme.scaffoldBackgroundColor,
          iconSize: 24,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          unselectedLabelStyle: theme.textTheme.labelSmall,
          items: [
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline),
                  Positioned(
                    top: -5,
                    right: -6,
                    child: UnconstrainedBox(
                      child: TencentCloudChatConversationTotalUnreadCount(
                        builder: (BuildContext _, int totalUnreadCount) {
                          if (totalUnreadCount == 0) {
                            return const SizedBox.shrink();
                          }
                          final displayText = totalUnreadCount > 99 ? "99+" : "$totalUnreadCount";
                          final isLargeText = displayText.length > 2;
                          return Semantics(
                            label: AppLocalizations.of(context)!.unreadMessagesSemantics(totalUnreadCount),
                            container: true,
                            child: UnconstrainedBox(
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: EdgeInsets.symmetric(horizontal: isLargeText ? 5 : 4),
                                decoration: BoxDecoration(
                                  color: AppThemeConfig.errorColor,
                                  borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      displayText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                            color: scheme.onError,
                                            fontWeight: FontWeight.w600,
                                            height: 1.0,
                                            fontSize: 10,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
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
              activeIcon: const Icon(Icons.chat_bubble),
              label: l10n.chats,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.contacts_outlined),
              activeIcon: const Icon(Icons.contacts),
              label: l10n.contacts,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.apps_outlined),
              activeIcon: const Icon(Icons.apps),
              label: l10n.applications,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }

  /// Build the central pane of the home page.
  ///
  /// UIKit's `TencentCloudChatConversation` widget owns its own master-detail
  /// layout (driven by `TencentCloudChatConversationConfig.forceDesktopLayout`)
  /// — see `build` where we set that config from `shouldShowMasterDetail` on
  /// every frame. Wrapping the IndexedStack in another Row here would create
  /// nested master-detail; collapse to the simple stack and let UIKit decide.
  Widget _buildMainPane(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: _buildTabChildren(),
    );
  }

  /// The IndexedStack children corresponding to the bottom-nav / sidebar
  /// tabs. Extracted from the inline `build` because the master-detail
  /// layout needs to reuse it inside a sized container.
  List<Widget> _buildTabChildren() {
    return [
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          // `setLocale` is driven by the global locale listener installed in
          // `initState` — no per-build scheduling needed here.
          return TencentCloudChatConversation(
            key: ValueKey('uikit-conversation-${locale.languageCode}'),
          );
        },
      ),
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: AppTheme.mode,
            builder: (context, themeMode, __) {
              return Stack(
                children: [
                  TencentCloudChatThemeWidget(
                    build: (context, themeColors, textStyles) {
                      return TencentCloudChatContact(
                        key: ValueKey(
                            'uikit-contact-${locale.languageCode}-${themeMode.name}'),
                      );
                    },
                  ),
                  Positioned(
                    // Offset below the UIKit AppBar so the FAB doesn't sit on
                    // top of the title. `kToolbarHeight` (56) + a small gap
                    // mirrors the inset Material uses for action buttons; on
                    // tablet the button lives in the sidebar pane which has
                    // its own header above it, so the offset still clears.
                    top: kToolbarHeight + AppSpacing.sm,
                    right: AppSpacing.xl,
                    // Top + right SafeArea so the button clears the status
                    // bar / Dynamic Island and right rounded corners on
                    // phones in landscape.
                    child: SafeArea(
                      left: false,
                      bottom: false,
                      child: NewEntryButton(
                        onAddFriend: _showAddFriendDialog,
                        onCreateGroup: _showAddGroupDialog,
                        onJoinIrcChannel: _ircAppInstalled
                            ? _showJoinIrcChannelDialog
                            : null,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) => ApplicationsPage(
          key: ValueKey('applications-${locale.languageCode}'),
          service: widget.service,
        ),
      ),
      SettingsPage(
        service: widget.service,
        connectionStatusStream: widget.service.connectionStatusStream,
        autoAcceptFriends: _autoAcceptFriends,
        onAutoAcceptFriendsChanged: _setAutoAcceptFriends,
        autoAcceptGroupInvites: _autoAcceptGroupInvites,
        onAutoAcceptGroupInvitesChanged: _setAutoAcceptGroupInvites,
      ),
    ];
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

  /// Desktop-style right-click menu for a conversation row.
  ///
  /// Anchored at the global cursor `position` reported by UIKit. Keeps the
  /// item list short (4 actions max — Pin/Unpin, Mark as read, Delete) to
  /// match the popup-menu density convention.
  Future<void> _showConversationContextMenu(
    V2TimConversation conv,
    Offset position,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final isPinned = conv.isPinned ?? false;
    final hasUnread = (conv.unreadCount ?? 0) > 0;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                size: 18,
                color: scheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(isPinned ? l10n.unpinConversation : l10n.pinConversation),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'mark_read',
          enabled: hasUnread,
          child: Row(
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 18,
                color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.markConversationAsRead),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: scheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.delete, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;

    final convId = conv.conversationID;
    switch (selected) {
      case 'pin':
        try {
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .pinConversation(
                conversationID: convId,
                isPinned: !isPinned,
              );
        } catch (e, st) {
          AppLogger.logError(
              '[HomePage] pinConversation failed for $convId', e, st);
        }
        break;
      case 'mark_read':
        try {
          // `cleanConversationUnreadMessageCount` is the non-deprecated entry
          // point that works for both C2C and group conversations. Passing
          // 0/0 marks everything currently in the conversation as read.
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .cleanConversationUnreadMessageCount(
                conversationID: convId,
                cleanTimestamp: 0,
                cleanSequence: 0,
              );
        } catch (e, st) {
          AppLogger.logError(
              '[HomePage] cleanConversationUnreadMessageCount failed for $convId',
              e,
              st);
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: Text(l10n.deleteConversationTitle),
                content: Text(
                  l10n.deleteConversationBody(conv.showName ?? convId),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            ) ??
            false;
        if (!mounted || !confirmed) return;
        try {
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .deleteConversation(conversationID: convId);
        } catch (e, st) {
          AppLogger.logError(
              '[HomePage] deleteConversation failed for $convId', e, st);
        }
        break;
    }
  }

  /// Show user profile page - uses router which handles desktop/mobile modes.
  ///
  /// Sets `_inContactProfileContext = true` while the profile route is on
  /// screen so `_onTapContactItem` can distinguish a Send Message tap from
  /// inside the profile from a contact-list tap on the underlying tab.
  /// The flag is cleared after the route returns; `_onTapContactItem` also
  /// clears it on the Send-Message path (it pops the profile itself).
  void _showUserProfileOnRight(BuildContext context, String userID) {
    _inContactProfileContext = true;
    final future = TencentCloudChatRouter().navigateTo(
      context: context,
      routeName: TencentCloudChatRouteNames.userProfile,
      options: TencentCloudChatUserProfileOptions(userID: userID),
    );
    // navigateTo returns dynamic; coerce to Future so we can clear the flag
    // when the user dismisses the profile via normal back navigation.
    if (future is Future) {
      unawaited(future.whenComplete(() {
        if (mounted) {
          _inContactProfileContext = false;
        }
      }));
    }
  }

  void _selectConversation({String? peerId, String? groupId}) {
    final bool hasPeer = peerId != null && peerId.isNotEmpty;
    final bool hasGroup = groupId != null && groupId.isNotEmpty;
    if (!hasPeer && !hasGroup) {
      widget.service.setActivePeer(null);
      return;
    }
    final String targetConvId = hasGroup ? 'group_$groupId' : 'c2c_${peerId!}';

    V2TimConversation? target;
    for (final conv in UikitDataFacade.conversationList) {
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
    UikitDataFacade.currentConversation = target;
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
      } catch (e, st) {
        AppLogger.logError(
            '[HomePage] acceptFriendRequest failed for $uid', e, st);
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
  Future<void> _loadPersistedGroupsIntoUIKit() =>
      _groupController.loadPersistedGroupsIntoUIKit();

  Future<void> _handleGroupChanged(String groupId, {String? displayName}) =>
      _groupController.handleGroupChanged(groupId, displayName: displayName);

  /// Dialog inset on narrow phones — Flutter's default symmetric(40, 24)
  /// leaves only ~240pt of usable width on a 320pt iPhone SE, which
  /// crowds the form. We tighten the horizontal inset on viewports below
  /// 400pt so the dialog can use the full responsive cap defined inside
  /// the dialog body (clamp 280-480/560).
  EdgeInsets _dialogInset(BuildContext ctx) {
    final w = MediaQuery.sizeOf(ctx).width;
    return w < 400
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  }

  Future<void> _showAddFriendDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: _dialogInset(ctx),
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
        insetPadding: _dialogInset(ctx),
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
      _showErrorSnackBar(appL10n.ircAppNotInstalled);
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
        _showErrorSnackBar(appL10n.ircChannelAddFailed);
      }
    } catch (e) {
      final appL10n = AppLocalizations.of(context);
      _showErrorSnackBar('${appL10n?.failed ?? 'Failed'}: $e');
    }
  }

  void _showSnackBar(String message) {
    final ctx = _scaffoldMessengerContext;
    if (ctx == null) return;
    AppSnackBar.show(ctx, message);
  }

  /// Error-styled snackbar variant for failure paths (friend request
  /// failed, IRC join failed, etc). Backed by the same AppSnackBar helper
  /// so it picks up the central error color + 4s duration.
  void _showErrorSnackBar(String message) {
    final ctx = _scaffoldMessengerContext;
    if (ctx == null) return;
    AppSnackBar.showError(ctx, message);
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        title: Text(AppLocalizations.of(context)!.messageReceivers(receivers.length.toString())),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: receivers.length,
            itemBuilder: (context, index) {
              final userId = receivers[index];
              final nickname = friendMap[userId] ?? userId;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  foregroundColor: scheme.primary,
                  child: Text(
                    nickname.isNotEmpty ? nickname.substring(0, 1).toUpperCase() : '?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                title: Text(
                  nickname.isNotEmpty ? nickname : userId,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                subtitle: Text(
                  userId,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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

// ---------------------------------------------------------------------------
// Desktop keyboard shortcut intents
// ---------------------------------------------------------------------------
// Each intent is a marker type — the matching `CallbackAction` lives inline
// in `HomePage.build` so it can close over local state (`setState`,
// `_showAddFriendDialog`, etc.).
class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _CloseWindowIntent extends Intent {
  const _CloseWindowIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}
