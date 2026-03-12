import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../util/locale_controller.dart';
import '../util/tox_utils.dart';
import '../util/theme_controller.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/fake_models.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_provider.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import '../adapters/event_bus_adapter.dart';
import '../adapters/conversation_manager_adapter.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
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
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
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
import '../util/prefs.dart';
import '../util/platform_utils.dart';
import 'add_friend_dialog.dart';
import 'add_group_dialog.dart';
import 'home/home_widgets.dart';
import '../util/irc_app_manager.dart';
import 'applications/irc_channel_dialog.dart';
import '../util/responsive_layout.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'widgets/app_snackbar.dart';


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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // HYBRID MODE: Using both binary replacement (for most operations) and Platform interface (for history queries)
    // This allows:
    // - Most operations to use binary replacement (TIMManager.instance -> NativeLibraryManager -> Dart* functions)
    // - History queries to use Platform interface (Tim2ToxSdkPlatform -> FfiChatService -> MessageHistoryPersistence)
    // This ensures history messages are loaded from persistence service instead of returning empty list from C++ layer
    
    // OPTIMIZATION: FakeUIKit is now started earlier in the startup flow (in _StartupGate)
    // Only start if not already started to avoid duplicate initialization
    if (!FakeUIKit.instance.isStarted) {
      FakeUIKit.instance.startWithFfi(widget.service);
    }
    
    // Set Platform interface for history queries and other operations that need persistence
    if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
      // Only set if not already set (avoid overwriting if already configured)
      // Create adapters for conversation manager and event bus
      final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
      final conversationManagerAdapter = ConversationManagerAdapter(
        FakeUIKit.instance.conversationManager!,
      );
      
      final platform = Tim2ToxSdkPlatform(
        ffiService: widget.service,
        eventBusProvider: eventBusAdapter,
        conversationManagerProvider: conversationManagerAdapter,
      );
      TencentCloudChatSdkPlatform.instance = platform;
      // When a group message is received via native path, update unread so sidebar and conversation list show it
      platform.onGroupMessageReceivedForUnread = (groupId) {
        if (groupId != null && groupId.isNotEmpty) {
          widget.service.incrementGroupUnread(groupId);
        }
        FakeUIKit.instance.im?.refreshConversations(); // update conversation list unread badges
        FakeUIKit.instance.im?.refreshUnreadTotal();
      };
      AppLogger.debug('[HomePage] Set TencentCloudChatSdkPlatform.instance to Tim2ToxSdkPlatform for history queries');
    }

    // Initialize CallServiceManager now that TencentCloudChatSdkPlatform.instance
    // is set to Tim2ToxSdkPlatform (CallBridgeService needs the real platform for signaling listeners)
    FakeUIKit.instance.callServiceManager?.initialize().then((_) {
      TencentCloudChat.instance.dataInstance.basic.useCallKit = true;
    }).catchError((e) {
      AppLogger.logError('[HomePage] CallServiceManager initialization error: $e');
    });
    
    AppLogger.debug('[HomePage] HYBRID MODE: Binary replacement + Platform interface');
    AppLogger.debug('[HomePage] TencentCloudChatSdkPlatform.instance type: ${TencentCloudChatSdkPlatform.instance.runtimeType}');
    
    // Initialize TIMManager SDK (required for binary replacement mode)
    // This ensures _isInitSDK is set to true and TIMGroupManager.instance.init() runs,
    // which initializes _groupListener. initGroupListener() must run AFTER this completes,
    // otherwise addGroupListener() triggers LateInitializationError.
    _initTIMManagerSDK().then((_) {
      // Initialize persistence hook for binary replacement scheme
      _initBinaryReplacementPersistenceHook();
      // Register UIKit group/friend listeners only after TIMGroupManager/TIMFriendshipManager
      // have been initialized by TIMManager.initSDK() (which runs in _initTIMManagerSDK).
      if (!mounted) return;
      TencentCloudChat.instance.chatSDKInstance.groupSDK.initGroupListener();
      AppLogger.debug('[HomePage] Registered UIKit group listener for GroupTipsEvent dispatch');
      TencentCloudChat.instance.chatSDKInstance.contactSDK.initFriendListener();
      AppLogger.debug('[HomePage] Registered UIKit friendship listener for friend event dispatch');
    }).catchError((e, stackTrace) {
      AppLogger.logError('[HomePage] Failed to initialize TIMManager SDK: $e', e, stackTrace);
    });
    
    // Inject provider to uikit
    ChatDataProviderRegistry.provider ??= FakeChatDataProvider(ffiService: widget.service);
    ChatMessageProviderRegistry.provider ??= FakeChatMessageProvider();
    // ContactActionProviderRegistry is no longer needed - Tim2ToxSdkPlatform handles friend operations
    
    // Manually register UIKit components to usedComponents map
    final basic = TencentCloudChat.instance.dataInstance.basic;
    basic.addUsedComponent(conv_pkg.TencentCloudChatConversationManager.register());
    
    // IMPORTANT: Register sticker plugin BEFORE message component registration
    // This ensures hasStickerPlugin and stickerPluginInstance are correctly set when message input initializes
    if (widget.service.selfId.isNotEmpty) {
      AppLogger.debug('[HomePage] initState: Registering sticker plugin early (before message component)');
      _tryRegisterStickerPluginSync();
    }
    
    // Override message widget builder to add key and null check for proper widget lifecycle
    // CRITICAL: We need to ensure complete widget disposal on conversation switch to prevent GlobalKey conflicts
    final messageRegisterResult = msg_pkg.TencentCloudChatMessageManager.register();
    // Ensure messageBuilder is initialized immediately after register() to prevent null issues
    // The register() method should create it, but we ensure it's set here as well
    final messageBuilder = msg_pkg.TencentCloudChatMessageManager.builder;
    basic.addUsedComponent((
      componentEnum: messageRegisterResult.componentEnum,
      widgetBuilder: ({required Map<String, dynamic> options}) {
        final userID = options["userID"] as String?;
        final groupID = options["groupID"] as String?;
        if (userID == null && groupID == null) {
          return const SizedBox.shrink();
        }
        final conversationID = groupID != null ? 'group_$groupID' : (userID != null ? 'c2c_$userID' : 'none');
        
        // Get the UniqueKey for this conversation (generated by event listener on conversation change)
        final widgetKey = _messageWidgetKeys[conversationID] ?? UniqueKey();
        
        // Use a stable ValueKey based on conversationID and counter to ensure widget is rebuilt on conversation change
        // The counter ensures that even if the same conversation is reopened, a new key is generated
        // This prevents GlobalKey conflicts from internal message item widgets
        final messageKey = ValueKey('msg-$conversationID-$_messageWidgetKeyCounter-${widgetKey.hashCode}');
        return msg_pkg.TencentCloudChatMessage(
          key: messageKey,
          options: TencentCloudChatMessageOptions(
            userID: userID,
            groupID: groupID,
            topicID: options["topicID"],
            targetMessage: options["targetMessage"],
          ),
        );
      },
    ));
    
    basic.addUsedComponent(contact_pkg.TencentCloudChatContactManager.register());

    // Group and friendship listeners are registered in _initTIMManagerSDK().then() above
    // so they run after TIMGroupManager.instance.init() (avoids LateInitializationError).

    // Configure group member list page builder to refresh data before opening
    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      groupMemberListPageBuilder: ({required V2TimGroupInfo groupInfo, required List<V2TimGroupMemberFullInfo> memberInfoList}) {
        // Use wrapper to refresh member list before opening
        return GroupMemberListWrapper(groupInfo: groupInfo, memberInfoList: memberInfoList);
      },
    );
    
    // Register search component
    final searchRegisterResult = search_pkg.CustomSearchManager.register();
    basic.addUsedComponent((
      componentEnum: searchRegisterResult.componentEnum,
      widgetBuilder: searchRegisterResult.widgetBuilder,
    ));
    
    // Override UIKit profile routes to show in sidebar-style without blocking the main window
    // This must be done AFTER UIKit components register their routes
    // Note: We use UIKit's default profile page to ensure all buttons work correctly
    // Profile page routing is now handled by tencent_cloud_chat_router.dart
    // which supports both desktop (dialog) and mobile (fullscreen) modes
    
    // Note: groupProfile route is handled by UIKit's dialog system in tencent_cloud_chat_router.dart
    // We don't need to register it here, as it will use the UIKit's default registration
    // which supports dialog-based navigation with proper options passing
    
    AppLogger.debug('[HomePage] initState: Calling _ensureStickerPluginRegistered');
    _ensureStickerPluginRegistered();
    _connectionStatusSub = widget.service.connectionStatusStream.listen((connected) async {
      AppLogger.log('[HomePage] Connection status changed: connected=$connected, selfId=${widget.service.selfId}');
      unawaited(_updateTray());
      if (connected) {
        // When connection is established, try to register sticker plugin if not already registered
        // This ensures plugin is registered even if selfId wasn't available during initState
        final selfId = widget.service.selfId;
        AppLogger.debug('[HomePage] Connection established: Checking plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId=$selfId, isEmpty=${selfId.isEmpty}');
        if (!_stickerPluginRegistered && selfId.isNotEmpty) {
          AppLogger.debug('[HomePage] Connection established: Scheduling plugin registration');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppLogger.debug('[HomePage] Connection established: PostFrameCallback executing, calling _tryRegisterStickerPlugin');
              _tryRegisterStickerPlugin();
            } else {
              AppLogger.debug('[HomePage] Connection established: PostFrameCallback skipped - not mounted');
            }
          });
        } else {
          AppLogger.debug('[HomePage] Connection established: Skipping plugin registration - already registered or selfId empty');
        }
        // When connection is established, sync persisted friends to Tox
        // Wait a bit for Tox friend list to be populated from savedata
        Future.delayed(const Duration(milliseconds: 2000), () async {
          if (mounted) {
            await _syncPersistedFriendsToTox();
          }
        });
      }
    });
    
    // Load and monitor LAN bootstrap service status (desktop only)
    if (PlatformUtils.isDesktop) {
      _loadBootstrapServiceStatus();
      _bootstrapServiceStatusTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _loadBootstrapServiceStatus(),
      );
    }
    
    // Listen to UIKit conversation unread count changes
    _conversationDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatConversationData<dynamic>>("TencentCloudChatConversationData")
        ?.listen((data) {
      // This prevents excessive rebuilds when switching conversations
      if (data.currentUpdatedFields == TencentCloudChatConversationDataKeys.currentConversation) {
        final currentConv = data.currentConversation;
        if (currentConv != null) {
          final conversationID = currentConv.conversationID;
          if (_currentConversationID != conversationID) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted && _currentConversationID != conversationID) {
                setState(() {
                  _messageWidgetKeys.clear();
                  _currentConversationID = conversationID;
                  _messageWidgetKeyCounter++;
                  _messageWidgetKeys[conversationID] = UniqueKey();
                });
              }
            });
          }
        }
      }
      if (data.currentUpdatedFields == TencentCloudChatConversationDataKeys.totalUnreadCount) {
        unawaited(_updateTray());
      }
    });
    
    // Listen to UIKit contact application unread count changes
    _contactDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>("TencentCloudChatContactData")
        ?.listen((data) {
      // When group list is updated, refresh conversations to ensure new groups appear in conversation list
      // But skip if this is triggered by a group quit (which is handled separately)
      if (data.currentUpdatedFields == TencentCloudChatContactDataKeys.groupList) {
        if (kDebugMode) debugPrint('[HomePage] Group list updated, refreshing conversations');
        // Delay slightly to ensure group persistence is complete
        // Note: We don't need to filter quitGroups here because _refreshConversations already does that
        Future.delayed(const Duration(milliseconds: 100), () {
          FakeUIKit.instance.im?.refreshConversations().catchError((e, stackTrace) {
            AppLogger.logError('[HomePage] Error refreshing conversations after group list update', e, stackTrace);
          });
        });
      }
      if (data.currentUpdatedFields == TencentCloudChatContactDataKeys.applicationCount ||
          data.currentUpdatedFields == TencentCloudChatContactDataKeys.applicationList) {
        unawaited(_updateTray());
      }
    });
    
    // Listen for group quit/dismiss events to refresh conversation list
    // This ensures conversation list is updated when groups are quit or dismissed
    _groupProfileDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatGroupProfileData<dynamic>>("TencentCloudChatGroupProfileData")
        ?.listen((data) async {
      // Prevent rapid successive membersChange events (potential loop)
      if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.membersChange) {
        final groupID = data.updateGroupID;
        if (groupID.isNotEmpty) {
          final lastChangeTime = _lastMembersChangeTime[groupID];
          if (lastChangeTime != null) {
            final timeSinceLastChange = DateTime.now().difference(lastChangeTime);
            if (timeSinceLastChange < _minMembersChangeInterval) {
              // Too soon, ignore this event to prevent loop
              if (kDebugMode) debugPrint('[HomePage] Ignoring rapid membersChange event for group $groupID (${timeSinceLastChange.inMilliseconds}ms ago)');
              return;
            }
          }
          _lastMembersChangeTime[groupID] = DateTime.now();
        }
      }
      if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.quitGroup) {
        final groupID = data.updateGroupID;
        if (kDebugMode) debugPrint('[HomePage] Group quit/dismissed: $groupID, removing from lists');

        // Note: deleteGroupInfoFromJoinedGroupList is already called in quitGroup/dismissGroup method,
        // so we don't need to call it again here to avoid infinite loop.
        // The quitGroup event is fired by deleteGroupInfoFromJoinedGroupList itself.

        // Ensure the group is removed from Prefs.getGroups()
        final savedGroups = await Prefs.getGroups();
        if (savedGroups.contains(groupID)) {
          savedGroups.remove(groupID);
          await Prefs.setGroups(savedGroups);
          if (kDebugMode) debugPrint('[HomePage] Removed group $groupID from Prefs.getGroups()');
        }

        // If the quit group is currently open in the chat window, navigate away.
        // Without this, the user can still send messages in the chat window after quitting,
        // which would re-add the conversation to the list.
        final convId = 'group_$groupID';
        final conversationData = TencentCloudChat.instance.dataInstance.conversation;
        if (_currentConversationID == convId) {
          if (kDebugMode) debugPrint('[HomePage] Quit group $groupID is currently open, clearing chat window');
          conversationData.currentConversation = null;
          if (mounted) {
            setState(() {
              _currentConversationID = null;
            });
          }
        }

        // Immediately remove the conversation from the conversation list
        // This ensures the UI updates immediately without waiting for refreshConversations
        conversationData.removeConversation([convId]);
        if (kDebugMode) debugPrint('[HomePage] Removed conversation $convId from conversation list');

        // Also trigger FakeGroupDeleted event to ensure fake_provider removes it from _convMap
        FakeUIKit.instance.eventBusInstance.emit(FakeIM.topicGroupDeleted, FakeGroupDeleted(groupID: groupID));
        if (kDebugMode) debugPrint('[HomePage] Emitted FakeGroupDeleted event for group $groupID');

        // Note: We don't call refreshConversations here because:
        // 1. We've already manually removed the conversation from the list
        // 2. We've triggered FakeGroupDeleted event to update _convMap
        // 3. refreshConversations might re-add the conversation if there's a race condition
        // The conversation will be properly filtered out in future refreshConversations calls
        // because we've added the group to quitGroups and removed it from knownGroups
      } else if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.builder) {
        // When builder is set, ensure groupID is populated if it's empty
        // This fixes the issue where groupID is empty when opening group profile page
        final groupProfileData = TencentCloudChat.instance.dataInstance.groupProfile;
        if (groupProfileData.updateGroupID.isEmpty || groupProfileData.updateGroupInfo.groupID.isEmpty) {
          // Use Future.microtask to handle async operations
          Future.microtask(() async {
            // Try to get groupID from current conversation first
            final currentConv = TencentCloudChat.instance.dataInstance.conversation.currentConversation;
            String? targetGroupID;
            V2TimGroupInfo? targetGroupInfo;
            
            if (currentConv?.groupID != null && currentConv!.groupID!.isNotEmpty) {
              targetGroupID = currentConv.groupID!;
            } else {
              // If no current conversation, try to get from the most recent group conversation
              final convList = TencentCloudChat.instance.dataInstance.conversation.conversationList;
              for (final conv in convList) {
                if (conv.groupID != null && conv.groupID!.isNotEmpty) {
                  targetGroupID = conv.groupID!;
                  break;
                }
              }
            }
            
            if (targetGroupID != null && targetGroupID.isNotEmpty) {
              // Try to get group info from contact data
              final contactData = TencentCloudChat.instance.dataInstance.contact;
              targetGroupInfo = contactData.getGroupInfo(targetGroupID);
              
              // If not found in contact data, try to get from groupList
              if (targetGroupInfo.groupID.isEmpty) {
                final groupList = contactData.groupList;
                final foundGroup = groupList.firstWhere(
                  (g) => g.groupID == targetGroupID,
                  orElse: () => V2TimGroupInfo(groupID: '', groupType: ''),
                );
                if (foundGroup.groupID.isNotEmpty) {
                  targetGroupInfo = foundGroup;
                }
              }
              
              // If still not found, create minimal group info
              if (targetGroupInfo.groupID.isEmpty) {
                // Get group name from preferences
                final groupName = await Prefs.getGroupName(targetGroupID);
                final groupAvatar = await Prefs.getGroupAvatar(targetGroupID);
                targetGroupInfo = V2TimGroupInfo(
                  groupID: targetGroupID,
                  groupType: "Work",
                  groupName: groupName ?? targetGroupID,
                  faceUrl: groupAvatar,
                );
              }
              
              // Update groupProfileData
              groupProfileData.updateGroupID = targetGroupID;
              groupProfileData.updateGroupInfo = targetGroupInfo;
            }
          });
        }
      }
    });
    
    // Use UIKit's built-in desktop split view (conversation list + message pane)
    conv_pkg.TencentCloudChatConversationManager.config.setConfigs(useDesktopMode: true);

    // Set global message config (applies to all message instances)
    msg_pkg.TencentCloudChatMessageManager.config.setConfigs(
      showSelfAvatar: createDefaultValue(true),
      showOthersAvatar: createDefaultValue(true),
      enableParseMarkdown: createDefaultValue(true),
      enableAutoReportReadStatusForComingMessages: createDefaultValue(true), // Enable auto report read status
      enabledGroupTypesForMessageReadReceipt: createDefaultValue<List<String>>(
        [GroupType.Work, GroupType.Public, GroupType.Meeting, GroupType.Community],
      ),
      attachmentConfig: createDefaultValue(
        TencentCloudChatMessageAttachmentConfig(
          enableSendImage: false,
          enableSendVideo: false,
          enableSendFile: true, // Enable file sending
          enableSearch: false, // Search entry unified above conversation list only
        ),
      ),
      // Enable message selection and forward in message menu
      defaultMessageMenuConfig: createDefaultValue(
        TencentCloudChatMessageDefaultMessageMenuConfig(
          enableMessageSelect: true, // Enable multi-select option in message menu
          enableMessageForward: true, // Enable forward option in message menu
          enableMessageCopy: true,
          enableMessageQuote: true,
          enableMessageRecall: true,
          enableMessageDeleteForSelf: true,
          enableGroupMessageReceipt: true,
        ),
      ),
      // Enable forward options in selection mode (individual and combined)
      defaultMessageSelectionOperationsConfig: createDefaultValue(
        TencentCloudChatMessageDefaultMessageSelectionOptionsConfig(
          enableMessageForwardIndividually: true, // Enable forward individually
          enableMessageForwardCombined: true, // Enable forward combined
          enableMessageDeleteForSelf: true,
        ),
      ),
      additionalAttachmentOptionsForMobile: ({String? userID, String? groupID, String? topicID}) {
        final appL10n = AppLocalizations.of(context)!;
        final photoLabel = appL10n.photo;
        final videoLabel = appL10n.video;
        return [
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
      },
      additionalInputControlBarOptionsForDesktop: ({String? userID, String? groupID, String? topicID}) {
        return _buildDesktopInputOptions(context, userID: userID, groupID: groupID);
      },
    );
    
    // Set global message builders
    msg_pkg.TencentCloudChatMessageManager.builder.setBuilders(
      messageNoChatBuilder: () => const TencentCloudChatMessageNoChat(),
      // Override messageInputBuilder to dynamically check plugin status
      // This fixes the issue where hasStickerPlugin is cached as class-level field
      messageInputBuilder: ({
        Key? key,
        MessageInputBuilderWidgets? widgets,
        required MessageInputBuilderData data,
        required MessageInputBuilderMethods methods,
      }) {
        // Dynamically check plugin status instead of using cached class-level fields
        final basic = TencentCloudChat.instance.dataInstance.basic;
        final hasStickerPlugin = basic.hasPlugins("sticker");
        final stickerPluginInstance = basic.getPlugin("sticker")?.pluginInstance;
        
        AppLogger.debug('[HomePage] messageInputBuilder: Dynamically checking plugin - hasStickerPlugin=$hasStickerPlugin, instance=${stickerPluginInstance != null}');
        
        // Create new data with updated plugin status
        final updatedData = MessageInputBuilderData(
          userID: data.userID,
          groupID: data.groupID,
          topicID: data.topicID,
          attachmentOptions: data.attachmentOptions,
          inSelectMode: data.inSelectMode,
          enableReplyWithMention: data.enableReplyWithMention,
          status: data.status,
          selectedMessages: data.selectedMessages,
          repliedMessage: data.repliedMessage,
          desktopMentionBoxPositionX: data.desktopMentionBoxPositionX,
          desktopMentionBoxPositionY: data.desktopMentionBoxPositionY,
          isGroupAdmin: data.isGroupAdmin,
          activeMentionIndex: data.activeMentionIndex,
          currentFilteredMembersListForMention: data.currentFilteredMembersListForMention,
          groupMemberList: data.groupMemberList,
          membersNeedToMention: data.membersNeedToMention,
          specifiedMessageText: data.specifiedMessageText,
          currentConversationShowName: data.currentConversationShowName,
          hasStickerPlugin: hasStickerPlugin, // Use dynamically checked value
          stickerPluginInstance: stickerPluginInstance, // Use dynamically checked value
        );
        
        // Use default widget with updated data
        // Import TencentCloudChatMessageInput from the correct path
        return TencentCloudChatMessageInput(
          key: key,
          data: updatedData,
          methods: methods,
          widgets: widgets,
        );
      },
      messageItemBuilder: ({
        Key? key,
        MessageItemBuilderWidgets? widgets,
        required MessageItemBuilderData data,
        required MessageItemBuilderMethods methods,
      }) {
        // Get the default message item widget
        final defaultWidget = widgets?.messageItemView ??
            TencentCloudChatMessageItemBuilders.getMessageItemBuilder(
              key: key,
              data: data,
              methods: methods,
            );
        
        // For group messages sent by self, add receiver count button
        final isGroupMessage = data.groupID != null && data.groupID!.isNotEmpty;
        final isSelfMessage = data.message.isSelf ?? false;
        final msgID = data.message.msgID ?? '';
        
        if (isGroupMessage && isSelfMessage && msgID.isNotEmpty) {
          // Get receiver count from FakeMessageManager
          final receiverCount = FakeUIKit.instance.messageManager?.getMessageReceiverCount(msgID) ?? 0;
          
          if (receiverCount > 0) {
            // Wrap the message with a receiver count button
            return Stack(
              children: [
                defaultWidget,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => _showMessageReceiversDialog(context, msgID, data.groupID!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 14,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$receiverCount',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        }
        
        return defaultWidget;
      },
    );
    
    // Keep FFI unread state in sync with whichever conversation UIKit opens
    final eventHandlers = conv_pkg.TencentCloudChatConversationManager.eventHandlers;
    final uiEventHandlers = eventHandlers.uiEventHandlers;
    
    uiEventHandlers.setEventHandlers(
      onTapConversationItem: ({
        required TencentCloudChatMessageOptions messageOptions,
        required V2TimConversation conversation,
        required bool inDesktopMode,
      }) async {
        final conversationID = conversation.conversationID;
        if (conversationID.isNotEmpty) {
          widget.service.setActivePeer(conversationID);
        }
        
        final convData = TencentCloudChat.instance.dataInstance.conversation;
        convData.currentConversation = conversation;
        
        return false;
      },
    );
    
    // Mark UIKit core as initialized & logged-in for rendering (we use fake backend)
    basic.updateInitializedStatus(status: true);
    basic.updateLoginStatus(status: true);
    // Provide current user for UIKit pages that assume non-null self info
    final selfId = widget.service.selfId;
    AppLogger.debug('[HomePage] _buildHomePage: Setting current user info, selfId=$selfId');
    basic.updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: selfId));
    
    // Check plugin status before attempting registration
    final hasPluginBefore = basic.hasPlugins("sticker");
    final pluginBefore = basic.getPlugin("sticker");
    AppLogger.debug('[HomePage] _buildHomePage: Plugin status before registration - hasPlugin=$hasPluginBefore, plugin=${pluginBefore != null}, instance=${pluginBefore?.pluginInstance}');
    
    // Ensure sticker plugin is registered after user info is available
    if (!_stickerPluginRegistered && selfId.isNotEmpty) {
      AppLogger.debug('[HomePage] _buildHomePage: Scheduling sticker plugin registration, selfId=$selfId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppLogger.debug('[HomePage] _buildHomePage: PostFrameCallback executing, calling _tryRegisterStickerPlugin');
          _tryRegisterStickerPlugin();
        } else {
          AppLogger.debug('[HomePage] _buildHomePage: PostFrameCallback skipped - not mounted');
        }
      });
    } else {
      AppLogger.debug('[HomePage] _buildHomePage: Skipping plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId.isEmpty=${selfId.isEmpty}');
    }
    
    // Verify plugin status after scheduling
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final hasPluginAfter = basic.hasPlugins("sticker");
        final pluginAfter = basic.getPlugin("sticker");
        AppLogger.debug('[HomePage] _buildHomePage: Plugin status after 500ms - hasPlugin=$hasPluginAfter, plugin=${pluginAfter != null}, instance=${pluginAfter?.pluginInstance}');
        if (pluginAfter != null) {
          AppLogger.debug('[HomePage] _buildHomePage: Plugin details - name=${pluginAfter.name}, initData=${pluginAfter.initData}');
        }
      }
    });
    
    // Initialize conversation controller with external provider support
    // Since we can't modify chat-uikit-flutter, we manually implement the external provider logic here
    final provider = ChatDataProviderRegistry.provider;
    if (provider != null) {
      // Use external data provider (e.g., fake SDK)
      // Seed initial conversations
      provider.getInitialConversations().then((list) {
        TencentCloudChat.instance.dataInstance.conversation.buildConversationList(list, 'external_init');
      });
      // Subscribe streams
      provider.conversationStream.listen((list) {
        TencentCloudChat.instance.dataInstance.conversation.buildConversationList(list, 'external_stream');
      });
      provider.totalUnreadStream.listen((total) {
        TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(total);
      });
    } else {
      // Default SDK flow - initialize the controller normally
      TencentCloudChatConversationController.instance.init();
    }
    // (defer to first build guarded init)
    // OPTIMIZATION: Reduced delay from 2000ms to 100ms for faster startup
    // FakeUIKit is now started earlier in the startup flow, so we don't need to wait as long
    // This allows friend list to be loaded and displayed faster
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (mounted) {
        await _load();
        // Sync persisted friends to Tox: re-add friends that are in local persistence but not in Tox
        // Only sync if we're connected (connection status will be checked in _syncPersistedFriendsToTox)
        if (widget.service.isConnected) {
          await _syncPersistedFriendsToTox();
        }
        // Load persisted groups into UIKit on startup
        // This ensures groups are visible in the group list even if contacts haven't been refreshed yet
        await _loadPersistedGroupsIntoUIKit();
        // Trigger FakeIM to refresh contacts to ensure UIKit contact list is populated
        // Note: im is guaranteed to be non-null since FakeUIKit is started earlier
        if (FakeUIKit.instance.im != null) {
          FakeUIKit.instance.im!.refreshContacts().catchError((e) {
            // Silently handle errors
          });
        }
      }
    });
    // Use 15s interval to reduce GetFriendList frequency (was 5s; fake_im still refreshes every 5s)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    Prefs.getLocalFriends().then((s) => setState(() => _localFriends = s));
    // Load auto-accept friends setting using Tox ID
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      Prefs.getAutoAcceptFriends(toxId).then((value) {
        if (mounted) {
          setState(() => _autoAcceptFriends = value);
        }
      });
      // Load auto-accept group invites setting
      Prefs.getAutoAcceptGroupInvites(toxId).then((value) {
        if (mounted) {
          setState(() => _autoAcceptGroupInvites = value);
          // Update FFI setting
          widget.service.setAutoAcceptGroupInvites(value);
        }
      });
    }
    // Check IRC app installation status
    _checkIrcAppStatus();
    _msgSub = widget.service.messages.listen((m) {
      if (widget.service.selfId == m.fromUserId) return;
      if (!mounted) return;
      setState(() {}); // refresh unread badges, no snackbar
      unawaited(_updateTray());
    });
    
    // Listen to file transfer progress updates
    // Note: Progress updates are handled in FakeChatMessageProvider
    widget.service.progressUpdates.listen((progress) {
      if (!mounted) return;
      // progress is: (peerId: String, path: String?, received: int, total: int, isSend: bool)
      if (!progress.isSend) {
        // File receiving progress - logged for debugging
        // Progress updates are handled in FakeChatMessageProvider which listens to the same stream
      }
    });
    
    // Listen to file transfer requests for large files (> 5MB) that require user confirmation
    // File requests are now handled by UIKit's download button
    // No need to show confirmation dialog - users can click the download button in the message
    // widget.service.fileRequests.listen((request) {
    //   // Removed: Large file confirmation dialog
    //   // UIKit's download button in file messages will handle downloads
    // });
    
    // Intercept UIKit's downloadMessage calls to trigger Tox file transfer
    // UIKit calls TencentCloudChatDownloadUtils.downloadMessage which calls SDK's downloadMessage
    // We need to intercept this at the SDK level, but since we can't modify UIKit code,
    // we'll use a workaround: listen for download progress callbacks and trigger file transfer
    // when a download is requested for a file that doesn't have a localUrl yet
    // Actually, better approach: override TencentCloudChatDownloadUtils.downloadMessage behavior
    // by patching it at runtime, or by listening to the download queue
    // For now, we'll use the UIKit event listener to handle 'fakeDownloadMessage' events
    // The SDK wrapper should emit this event when downloadMessage is called
    // Bridge fake contacts to UIKit Contact data
    _friendsSub = FakeUIKit.instance.eventBusInstance.on<List<FakeUser>>(FakeIM.topicContacts).listen((list) async {
      // Load avatar paths from local cache for all friends
      final mapped = await Future.wait(list.map((u) async {
        final avatarPath = await Prefs.getFriendAvatarPath(u.userID);
        // Only set faceUrl if avatarPath is not null and not empty
        // This ensures empty string is not set, allowing profile page to properly check for avatar
        final faceUrl = (avatarPath != null && avatarPath.isNotEmpty) ? avatarPath : null;
        return V2TimFriendInfo(
          userID: u.userID,
          friendRemark: u.nickName,
          userProfile: V2TimUserFullInfo(
            userID: u.userID, 
            nickName: u.nickName, 
            faceUrl: faceUrl,
            selfSignature: u.status.isNotEmpty ? u.status : null,
          ),
        );
      }));
      TencentCloudChat.instance.dataInstance.contact.buildFriendList(mapped, "home");
      // Sync removal: buildFriendList only adds/updates, never removes.
      // Remove friends from UIKit's contact list that are no longer in the fresh FakeIM list.
      // This ensures deleted friends don't persist in the contact list after FakeIM detects deletion.
      final freshUserIds = list.map((u) => u.userID).toSet();
      final currentContactList = TencentCloudChat.instance.dataInstance.contact.contactList;
      final staleUserIds = currentContactList
          .where((c) => !freshUserIds.contains(c.userID))
          .map((c) => c.userID ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (staleUserIds.isNotEmpty) {
        TencentCloudChat.instance.dataInstance.contact.deleteFromFriendList(staleUserIds, 'home_sync');
      }
      // Bridge online status to UIKit contact data
      // Only update friend statuses, don't overwrite self status from onUserStatusChanged
      final statuses = list
          .map((u) => V2TimUserStatus(userID: u.userID, statusType: u.online ? 1 : 0, onlineDevices: const []))
          .toList();
      if (statuses.isNotEmpty) {
        // buildUserStatusList will merge/update existing statuses, not replace all
        // This preserves self status that was set by onUserStatusChanged callback
        TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(statuses, "home");
      }
      
      // Also load groups into UIKit cache when contacts are loaded
      // This ensures group info is available for profile page and chat header
      final groups = widget.service.knownGroups;
      for (final gid in groups) {
        final savedName = await Prefs.getGroupName(gid);
        final savedAvatar = await Prefs.getGroupAvatar(gid);
        // Always add group info, even if name and avatar are null
        // This ensures UIKit has the latest state (null avatar means no avatar, not old cached avatar)
        final groupInfo = V2TimGroupInfo(
          groupID: gid,
          groupType: "work",
          groupName: savedName,
          faceUrl: savedAvatar, // Will be null if cleared, ensuring UIKit doesn't use old avatar
        );
        TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
      }
      
      // Persist friend list locally for cold start fallback
      // Ensure all friend IDs are normalized to 64 characters (Tox public key length)
      // Note: Tox friend IDs are 64 characters (public key), not 76 characters (full address)
      final friendIds = list.map((u) {
        final id = u.userID.trim();
        // Tox friend IDs are 64 characters (public key). If longer (e.g., 76-char address), extract only the first 64 characters.
        // If shorter, keep as is (might be a partial ID or different format)
        return id.length > 64 ? id.substring(0, 64) : id;
      }).toSet();
      // FakeIM._emitContactsWithFriendsImpl is the single authority for Prefs.localFriends.
      // It replaces Prefs with the authoritative Tox friend list after every emit.
      // We only update in-memory _localFriends to keep it in sync for UI purposes.
      if (mounted) {
        setState(() {
          _localFriends = friendIds;
        });
      }
    });

    // Replay the current contact list for late subscribers.
    // FakeIM may have already emitted contacts before _friendsSub was established
    // (e.g. 13+ second gap between FakeIM.start() and home_page initState).
    // forceRefreshContacts() resets the change-detection cache and re-emits,
    // so _friendsSub's listener above picks it up and calls buildFriendList.
    if (FakeUIKit.instance.im != null) {
      FakeUIKit.instance.im!.forceRefreshContacts().catchError((e) {
        AppLogger.debug('[HomePage] forceRefreshContacts after _friendsSub error: $e');
      });
    }

    _appsSub = FakeUIKit.instance.eventBusInstance.on<List<FakeFriendApplication>>(FakeIM.topicFriendApps).listen((list) async {
      final mapped =
          list.map((a) => V2TimFriendApplication(userID: a.userID, addWording: a.wording, type: 1, nickname: "", faceUrl: "")).toList();
      TencentCloudChat.instance.dataInstance.contact.buildApplicationList(mapped, "home");
      TencentCloudChat.instance.dataInstance.contact.setApplicationUnreadCount(mapped);
      _pendingFriendApps = List<V2TimFriendApplication>.from(mapped);
      if (_autoAcceptFriends && mapped.isNotEmpty) {
        // OPTIMIZATION: Accept friend applications asynchronously to avoid blocking UI
        // This allows the app to continue initializing while friend requests are being processed
        _acceptFriendApplications(mapped).catchError((e) {
          // Silently handle errors during async friend acceptance
        });
      }
      if (mounted) setState(() {});
      unawaited(_updateTray());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_updateTray());
    });
    
    // Configure ContactBuilder to ensure profile page shows all necessary components
    // Get original builders to preserve default behavior
    final originalContentBuilder = contact_pkg.TencentCloudChatContactManager.builder.getUserProfileContentBuilder;
    final originalStateBuilder = contact_pkg.TencentCloudChatContactManager.builder.getUserProfileStateButtonBuilder;
    final originalDeleteBuilder = contact_pkg.TencentCloudChatContactManager.builder.getUserProfileDeleteButtonBuilder;
    
    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      // Ensure content builder shows nickname and status (use default if not null)
      userProfileContentBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        // Use default builder which shows nickname and ID
        return originalContentBuilder(userFullInfo: userFullInfo);
      },
      // Ensure state button builder shows (use default)
      userProfileStateButtonBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        // Use default builder which shows do not disturb, pin, blacklist options
        return originalStateBuilder(userFullInfo: userFullInfo);
      },
      // Override delete button builder to show "Add Friend" for non-friends
      userProfileDeleteButtonBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        // Check if user is a friend
        // Normalize IDs for comparison (Tox IDs can be 64 or 76 characters)
        final friendIDList = TencentCloudChat.instance.dataInstance.contact.contactList
            .map((e) => normalizeToxId(e.userID))
            .toSet();
        final normalizedUserID = normalizeToxId(userFullInfo.userID ?? '');
        final isFriend = friendIDList.contains(normalizedUserID);
        
        if (isFriend) {
          // For friends, use default delete button (shows "Clear Chat History" and "Delete Contact")
          return originalDeleteBuilder(userFullInfo: userFullInfo);
        } else {
          // For non-friends, show "Add Friend" button
          return _buildAddFriendButton(userFullInfo);
        }
      },
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _msgSub?.cancel();
    _friendsSub?.cancel();
    _appsSub?.cancel();
    _connectionStatusSub?.cancel();
    _conversationDataSub?.cancel();
    _contactDataSub?.cancel();
    _groupProfileDataSub?.cancel();
    super.dispose();
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
                } catch (_) {
                  // If we can't get the path, just send the error message
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

  void _ensureStickerPluginRegistered() {
    AppLogger.debug('[HomePage] _ensureStickerPluginRegistered called: mounted=$mounted');
    if (!mounted) {
      AppLogger.debug('[HomePage] _ensureStickerPluginRegistered: Early return - not mounted');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.debug('[HomePage] _ensureStickerPluginRegistered: PostFrameCallback executing, mounted=$mounted');
      if (!mounted) {
        AppLogger.debug('[HomePage] _ensureStickerPluginRegistered: PostFrameCallback skipped - not mounted');
        return;
      }
      _tryRegisterStickerPlugin();
    });
    // Register other plugins
    AppLogger.debug('[HomePage] _ensureStickerPluginRegistered: Registering other plugins');
    _registerTextTranslatePlugin();
    _registerSoundToTextPlugin();
  }

  void _tryRegisterStickerPluginSync() {
    // Synchronous version for early registration in initState
    if (_stickerPluginRegistered) return;
    final userId = widget.service.selfId;
    if (userId.isEmpty) return;
    
    final basic = TencentCloudChat.instance.dataInstance.basic;
    if (basic.hasPlugins("sticker")) {
      _stickerPluginRegistered = true;
      AppLogger.debug('[HomePage] _tryRegisterStickerPluginSync: Plugin already registered');
      return;
    }
    
    AppLogger.debug('[HomePage] _tryRegisterStickerPluginSync: Registering sticker plugin synchronously');
    final stickerPlugin = TencentCloudChatStickerPlugin(context: context);
    final initDataObj = TencentCloudChatStickerInitData(
      userID: userId,
      useDefaultSticker: true,
      useDefaultCustomFace_4350: true,
      useDefaultCustomFace_4351: true,
      useDefaultCustomFace_4352: true,
    );
    final initData = initDataObj.toJson();
    
    // Initialize synchronously (this is a fire-and-forget operation)
    stickerPlugin.init(json.encode(initData)).then((initResult) {
      if (!mounted) return;
      basic.addPlugin(
        TencentCloudChatPluginItem(
          name: "sticker",
          initData: initData,
          pluginInstance: stickerPlugin,
        ),
      );
      _stickerPluginRegistered = true;
      AppLogger.debug('[HomePage] _tryRegisterStickerPluginSync: Plugin registered successfully');
    }).catchError((e, stackTrace) {
      AppLogger.logError('[HomePage] _tryRegisterStickerPluginSync: Failed to register: $e', e, stackTrace);
    });
  }

  void _tryRegisterStickerPlugin() {
    AppLogger.debug('[HomePage] _tryRegisterStickerPlugin called: _stickerPluginRegistered=$_stickerPluginRegistered, mounted=$mounted');
    if (_stickerPluginRegistered || !mounted) {
      AppLogger.debug('[HomePage] _tryRegisterStickerPlugin: Early return - already registered or not mounted');
      return;
    }
    final userId = widget.service.selfId;
    AppLogger.debug('[HomePage] _tryRegisterStickerPlugin: userId=$userId, isEmpty=${userId.isEmpty}');
    if (userId.isEmpty) {
      // selfId not available yet, will retry later
      AppLogger.debug('[HomePage] Sticker plugin: selfId not available yet, will retry when available');
      return;
    }
    final basic = TencentCloudChat.instance.dataInstance.basic;
    final hasPlugin = basic.hasPlugins("sticker");
    AppLogger.debug('[HomePage] _tryRegisterStickerPlugin: basic.hasPlugins("sticker")=$hasPlugin');
    if (hasPlugin) {
      final plugin = basic.getPlugin("sticker");
      AppLogger.debug('[HomePage] _tryRegisterStickerPlugin: Plugin already exists: ${plugin != null}, instance=${plugin?.pluginInstance}');
      _stickerPluginRegistered = true;
      AppLogger.debug('[HomePage] Sticker plugin already registered');
      return;
    }
    
    AppLogger.debug('[HomePage] Registering sticker plugin with userId: $userId');
    final stickerPlugin = TencentCloudChatStickerPlugin(context: context);
    // Enable default stickers to ensure sticker panel has content
    final initDataObj = TencentCloudChatStickerInitData(
      userID: userId,
      useDefaultSticker: true,
      useDefaultCustomFace_4350: true,
      useDefaultCustomFace_4351: true,
      useDefaultCustomFace_4352: true,
    );
    final initData = initDataObj.toJson();
    AppLogger.debug('[HomePage] Sticker initData: $initData');
    Future(() async {
      try {
        final initResult = await stickerPlugin.init(json.encode(initData));
        AppLogger.debug('[HomePage] Sticker plugin init result: $initResult');
        if (!mounted) return;
        basic.addPlugin(
          TencentCloudChatPluginItem(
            name: "sticker",
            initData: initData,
            pluginInstance: stickerPlugin,
          ),
        );
        _stickerPluginRegistered = true;
        AppLogger.debug('[HomePage] Sticker plugin registered successfully');
        
        // Trigger a notification to update components that depend on plugins
        // This ensures message input components can detect the newly registered plugin
        // We use a small delay to ensure the plugin is fully registered
        // Force message input components to re-check plugin status
        // Since hasStickerPlugin and stickerPluginInstance are class-level fields in UIKit,
        // we need to trigger a rebuild to make them re-read the plugin status
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            // Force a rebuild by updating basic data
            // This will cause components to re-check for plugins
            basic.notifyListener(TencentCloudChatBasicDataKeys.addUsedComponent as dynamic);
            AppLogger.debug('[HomePage] Triggered plugin update notification');
            
            // Also try to trigger conversation data update to force message components rebuild
            // This ensures message input components will re-read plugin status
            try {
              final conversationData = TencentCloudChat.instance.dataInstance.conversation;
              final currentConv = conversationData.currentConversation;
              if (currentConv != null) {
                // Trigger a conversation update to force message components to rebuild
                conversationData.notifyListener(TencentCloudChatConversationDataKeys.currentConversation as dynamic);
                AppLogger.debug('[HomePage] Triggered conversation update to force message component rebuild');
              }
            } catch (e) {
              AppLogger.logError('[HomePage] Failed to trigger conversation update: $e', e, StackTrace.current);
            }
            
            // Also trigger basic data update to notify listeners about plugin registration
            // This will trigger the listener in message input container to rebuild attachment options
            try {
              basic.notifyListener(TencentCloudChatBasicDataKeys.addUsedComponent as dynamic);
              AppLogger.debug('[HomePage] Triggered basic data update for plugin registration');
            } catch (e) {
              AppLogger.logError('[HomePage] Failed to trigger basic data update: $e', e, StackTrace.current);
            }
          }
        });
        // Verify plugin is accessible
        final plugin = basic.getPlugin("sticker");
        AppLogger.debug('[HomePage] Plugin verification: plugin=${plugin != null}');
        if (plugin != null) {
          AppLogger.debug('[HomePage] Sticker plugin verified: name=${plugin.name}, instance=${plugin.pluginInstance}, initData=${plugin.initData}');
          // Test getWidget to ensure it works
          try {
            AppLogger.debug('[HomePage] Testing getWidget("stickerPanel")...');
            final widget = await plugin.pluginInstance.getWidget(methodName: "stickerPanel");
            AppLogger.debug('[HomePage] Sticker panel widget retrieved: ${widget != null}, type=${widget.runtimeType}');
            if (widget == null) {
              AppLogger.debug('[HomePage] ERROR: getWidget returned null!');
            }
          } catch (e, stackTrace) {
            AppLogger.logError('[HomePage] Failed to get sticker panel widget: $e', e, stackTrace);
          }
          
          // Verify plugin instance methods
          AppLogger.debug('[HomePage] Plugin instance type: ${plugin.pluginInstance.runtimeType}');
          if (plugin.pluginInstance is TencentCloudChatStickerPlugin) {
            final stickerPlugin = plugin.pluginInstance as TencentCloudChatStickerPlugin;
            AppLogger.debug('[HomePage] Plugin is TencentCloudChatStickerPlugin, initData.userID=${TencentCloudChatStickerPlugin.initData.userID}');
            AppLogger.debug('[HomePage] Plugin initData.customStickerLists: ${TencentCloudChatStickerPlugin.initData.customStickerLists?.length ?? 0} items');
          }
        } else {
          AppLogger.debug('[HomePage] WARNING: Sticker plugin not found after registration!');
          AppLogger.debug('[HomePage] Available plugins: ${basic.plugins.map((p) => p.name).join(", ")}');
        }
        
        // Final verification
        final finalCheck = basic.hasPlugins("sticker");
        final finalPlugin = basic.getPlugin("sticker");
        AppLogger.debug('[HomePage] Final plugin check: hasPlugins=$finalCheck, getPlugin=${finalPlugin != null}');
      } catch (e, stackTrace) {
        AppLogger.logError('[HomePage] Failed to register sticker plugin: $e', e, stackTrace);
        // Don't set _stickerPluginRegistered = true on error, so we can retry
      }
    });
  }

  void _registerTextTranslatePlugin() {
    if (_textTranslatePluginRegistered || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _textTranslatePluginRegistered) return;
      final basic = TencentCloudChat.instance.dataInstance.basic;
      if (!basic.hasPlugins("textTranslate")) {
        final plugin = TencentCloudChatTextTranslate(
          onTranslateFailed: () {
          },
          onTranslateSuccess: (localCustomData) {
          },
        );
        basic.addPlugin(
          TencentCloudChatPluginItem(
            name: "textTranslate",
            pluginInstance: plugin,
          ),
        );
        _textTranslatePluginRegistered = true;
      } else {
        _textTranslatePluginRegistered = true;
      }
    });
  }

  void _registerSoundToTextPlugin() {
    if (_soundToTextPluginRegistered || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _soundToTextPluginRegistered) return;
      final basic = TencentCloudChat.instance.dataInstance.basic;
      if (!basic.hasPlugins("soundToText")) {
        final plugin = TencentCloudChatSoundToText();
        basic.addPlugin(
          TencentCloudChatPluginItem(
            name: "soundToText",
            pluginInstance: plugin,
          ),
        );
        _soundToTextPluginRegistered = true;
      } else {
        _soundToTextPluginRegistered = true;
      }
    });
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
        } catch (_) {}
      });
    } catch (_) {}
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

  /// Initialize TIMManager SDK (required for binary replacement mode)
  /// This ensures _isInitSDK is set to true, allowing SDK operations to work
  /// 
  /// Standard pattern from chat-demo-flutter:
  /// - chat-demo-flutter calls TencentCloudChat.controller.initUIKit() which internally
  ///   calls TUILogin.instance.login() for non-Web platforms
  /// - TUILogin.instance.login() automatically calls initSDK before login
  /// - Since we're using binary replacement mode with FfiChatService, we need to manually
  ///   call initSDK to ensure _isInitSDK is set to true
  Future<void> _initTIMManagerSDK() async {
    try {
      // Check if SDK is already initialized
      if (TIMManager.instance.isInitSDK()) {
        AppLogger.debug('[HomePage] TIMManager SDK already initialized');
        return;
      }
      
      AppLogger.debug('[HomePage] Initializing TIMManager SDK...');
      
      // Initialize SDK with a dummy SDKAppID (0 is used as placeholder)
      // The actual SDK initialization is done by FfiChatService.init() which calls tim2tox_ffi_init()
      // This call ensures _isInitSDK is set to true by calling DartInitSDK in the C++ layer
      final result = await TIMManager.instance.initSDK(
        sdkAppID: 0, // Placeholder, actual initialization is done by FfiChatService
        logLevel: LogLevelEnum.V2TIM_LOG_INFO,
        uiPlatform: 0, // Flutter FFI platform (APIType::FlutterFFI: 0x1 << 6 = 64)
      );
      
      if (result) {
        AppLogger.log('[HomePage] TIMManager SDK initialized successfully, _isInitSDK=${TIMManager.instance.isInitSDK()}');
      } else {
        AppLogger.debug('[HomePage] TIMManager SDK initialization failed, _isInitSDK=${TIMManager.instance.isInitSDK()}');
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] Error initializing TIMManager SDK: $e', e, stackTrace);
    }
  }
  
  /// Initialize binary replacement persistence hook
  /// 
  /// Sets up message persistence for binary replacement scheme by:
  /// 1. Initializing the hook with persistence service and self ID
  /// 2. Adding a wrapped message listener that automatically saves received messages
  void _initBinaryReplacementPersistenceHook() {
    try {
      // Get persistence service from FfiChatService
      final persistence = widget.service.messageHistoryPersistence;
      final selfId = widget.service.selfId;
      
      if (selfId.isEmpty) {
        AppLogger.debug('[HomePage] Self ID not available yet, will initialize hook after login');
        // Wait for selfId to be available
        widget.service.connectionStatusStream.listen((connected) {
          if (connected && widget.service.selfId.isNotEmpty) {
            _setupPersistenceHook(persistence, widget.service.selfId);
          }
        });
        return;
      }
      
      _setupPersistenceHook(persistence, selfId);
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] Error initializing persistence hook: $e', e, stackTrace);
    }
  }
  
  void _setupPersistenceHook(MessageHistoryPersistence persistence, String selfId) {
    try {
      // Initialize the hook
      BinaryReplacementHistoryHook.initialize(persistence, selfId);
      
      // Get the current message listener (if any)
      final currentListeners = TIMMessageManager.instance.v2TimAdvancedMsgListenerList;
      
      // Create a wrapped listener that saves messages
      if (currentListeners.isNotEmpty) {
        // Wrap the first listener (usually the UIKit's listener)
        final originalListener = currentListeners.first;
        final wrappedListener = BinaryReplacementHistoryHook.wrapListener(originalListener);
        
        // Remove original and add wrapped
        TIMMessageManager.instance.removeAdvancedMsgListener(listener: originalListener);
        TIMMessageManager.instance.addAdvancedMsgListener(wrappedListener);
        
        AppLogger.debug('[HomePage] Binary replacement persistence hook initialized');
      } else {
        // No listener yet, create a new one that saves messages
        final listener = V2TimAdvancedMsgListener(
          onRecvNewMessage: (V2TimMessage message) {
            // Save message to persistence
            BinaryReplacementHistoryHook.saveMessage(message);
          },
        );
        TIMMessageManager.instance.addAdvancedMsgListener(listener);
        AppLogger.debug('[HomePage] Binary replacement persistence hook initialized (new listener)');
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] Error setting up persistence hook: $e', e, stackTrace);
    }
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
