import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import 'notification_service.dart';

/// Hooks the V2TimAdvancedMsgListener path and posts an OS-level notification
/// whenever a new message arrives that the user should be told about.
///
/// Suppression rules (matches the prompt's contract):
///   - Self-sent messages (message.isSelf == true OR sender == loginUserID)
///   - The app is in the foreground AND the active conversation matches the
///     message's conversation (the user is already looking at it)
///   - Conversation is muted (best-effort: read from the V2TimConversation
///     when available, fall back to "not muted")
///
/// Registration is idempotent: [register] guards on [_registered] so calling
/// twice from HomePage doesn't double-listen. The Tim2Tox platform's
/// listener list is per-instance and we don't have a stable handle back to
/// remove the listener once it's registered — by design this listener lives
/// for the lifetime of the session.
class NotificationMessageListener {
  NotificationMessageListener._(this._service);

  static NotificationMessageListener? _instance;

  /// Returns the singleton, lazily constructed against the given service.
  /// Subsequent calls ignore the [service] argument — the first caller wins
  /// the binding.
  static NotificationMessageListener forService(FfiChatService service) {
    return _instance ??= NotificationMessageListener._(service);
  }

  final FfiChatService _service;
  V2TimAdvancedMsgListener? _listener;
  bool _registered = false;
  StreamSubscription<String>? _onTapSub;

  /// Registers the listener with the SDK. Idempotent.
  ///
  /// [onConversationTapped] (optional) is invoked when the user taps a
  /// notification. The payload is a conversation ID like `c2c_<toxId>` or
  /// `group_<groupId>` — the same identifier we use elsewhere.
  Future<void> register({
    ValueChanged<String>? onConversationTapped,
  }) async {
    if (_registered) {
      AppLogger.debug(
          '[NotificationMessageListener] register() called twice; ignoring');
      // Update the tap handler if a new one was supplied, even on a repeat
      // call — caller may have remounted HomePage and wants the new routing
      // closure.
      if (onConversationTapped != null) {
        await _onTapSub?.cancel();
        _onTapSub = NotificationService.instance.onSelectStream
            .listen(onConversationTapped);
      }
      return;
    }

    // Make sure the service is ready before we start posting.
    await NotificationService.instance.init();

    _listener = V2TimAdvancedMsgListener(
      onRecvNewMessage: _onRecvNewMessage,
    );
    try {
      await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .addAdvancedMsgListener(listener: _listener!);
      _registered = true;
      AppLogger.info(
          '[NotificationMessageListener] Registered V2TimAdvancedMsgListener');
    } catch (e, st) {
      AppLogger.logError(
          '[NotificationMessageListener] Failed to register listener', e, st);
      return;
    }

    if (onConversationTapped != null) {
      _onTapSub = NotificationService.instance.onSelectStream
          .listen(onConversationTapped);
    }

    // Replay the cold-start payload (if any) once a tap handler exists.
    if (onConversationTapped != null) {
      final launchPayload = NotificationService.instance.consumeLaunchPayload();
      if (launchPayload != null && launchPayload.isNotEmpty) {
        // Defer to next microtask so the caller's wiring has time to settle.
        scheduleMicrotask(() => onConversationTapped(launchPayload));
      }
    }
  }

  /// Cancel the tap subscription if any. The SDK-level listener stays
  /// registered for the rest of the session — there's no clean per-listener
  /// removal that's safe to drive from HomePage dispose without races.
  Future<void> dispose() async {
    await _onTapSub?.cancel();
    _onTapSub = null;
  }

  void _onRecvNewMessage(V2TimMessage message) {
    try {
      if (_shouldSuppress(message)) return;
      final senderName = _resolveSenderName(message);
      final conversationId = _resolveConversationId(message);
      if (conversationId == null) {
        AppLogger.debug(
            '[NotificationMessageListener] Skipping: no conversationId for msgID=${message.msgID}');
        return;
      }
      final preview = _buildPreview(message);
      // Avatar best-effort — only resolves a path for C2C messages where we
      // have the sender's friend avatar cached in Prefs. Group avatars are
      // intentionally skipped to keep the path resolution off the hot path.
      _resolveAvatar(message).then((avatarPath) {
        NotificationService.instance.showMessageNotification(
          conversationId: conversationId,
          senderName: senderName,
          preview: preview,
          avatarPath: avatarPath,
        );
      });
    } catch (e, st) {
      AppLogger.logError(
          '[NotificationMessageListener] Error handling new message', e, st);
    }
  }

  bool _shouldSuppress(V2TimMessage message) {
    // Self-sent guard. Check both isSelf and sender vs the session's selfId
    // because some control-signal paths land with isSelf unset.
    if (message.isSelf ?? false) return true;
    final sender = message.sender ?? '';
    if (sender.isNotEmpty && sender == _service.selfId) return true;

    // Skip control-signal text messages that bubble up as plain text but
    // shouldn't trigger a notification (revoke / face / custom / location).
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT) {
      final text = message.textElem?.text ?? '';
      if (text.startsWith('__revoke__:')) return true;
    }

    // Foreground + active conversation guard. The user shouldn't get a
    // banner for the chat they're actively looking at.
    final lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    final isFocused = lifecycle == AppLifecycleState.resumed;
    final activeConv = UikitDataFacade.currentConversation;
    final activeConvId = activeConv?.conversationID;
    final messageConvId = _resolveConversationId(message);
    if (isFocused &&
        activeConvId != null &&
        messageConvId != null &&
        activeConvId == messageConvId) {
      return true;
    }

    // Mute guard — best-effort. The conversation list cached by UIKit
    // exposes `recvOpt` (0 = receive, 1 = no notify, 2 = block); when it's
    // not 0 we suppress the banner. The conversation may not be in the
    // cache yet for a brand-new contact, in which case we err on the side
    // of notifying.
    try {
      if (messageConvId != null) {
        final convs = UikitDataFacade.conversationList;
        for (final c in convs) {
          if (c.conversationID == messageConvId) {
            final recvOpt = c.recvOpt;
            if (recvOpt != null && recvOpt != 0) return true;
            break;
          }
        }
      }
    } catch (e) {
      // Don't let a UIKit data-layer hiccup block the notification.
      AppLogger.debug(
          '[NotificationMessageListener] mute lookup failed: $e (continuing)');
    }

    return false;
  }

  String _resolveSenderName(V2TimMessage message) {
    // Priority: friendRemark > nickName > sender (toxId) > "Unknown".
    final remark = message.friendRemark;
    if (remark != null && remark.isNotEmpty) return remark;
    final nick = message.nickName;
    if (nick != null && nick.isNotEmpty) return nick;
    final sender = message.sender;
    if (sender != null && sender.isNotEmpty) {
      // Trim long Tox IDs to the first 12 chars so the banner title isn't
      // a 76-char hex blob.
      if (sender.length > 16) {
        return '${sender.substring(0, 12)}…';
      }
      return sender;
    }
    return 'New message';
  }

  /// Returns `c2c_<userID>` or `group_<groupID>` to match the rest of the
  /// app's conversation identifier scheme. Returns null when we can't
  /// determine either.
  String? _resolveConversationId(V2TimMessage message) {
    final groupId = message.groupID;
    if (groupId != null && groupId.isNotEmpty) {
      return 'group_$groupId';
    }
    final userId = message.userID;
    if (userId != null && userId.isNotEmpty) {
      return 'c2c_$userId';
    }
    final sender = message.sender;
    if (sender != null && sender.isNotEmpty) {
      return 'c2c_$sender';
    }
    return null;
  }

  String _buildPreview(V2TimMessage message) {
    switch (message.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
        final text = message.textElem?.text ?? '';
        if (text.isEmpty) return '[Message]';
        return text;
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
        return '[Image]';
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        return '[Video]';
      case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
        final dur = message.soundElem?.duration;
        if (dur != null && dur > 0) return '[Voice ${dur}s]';
        return '[Voice]';
      case MessageElemType.V2TIM_ELEM_TYPE_FILE:
        final name = message.fileElem?.fileName;
        if (name != null && name.isNotEmpty) return '[File] $name';
        return '[File]';
      case MessageElemType.V2TIM_ELEM_TYPE_FACE:
        return '[Sticker]';
      case MessageElemType.V2TIM_ELEM_TYPE_LOCATION:
        return '[Location]';
      case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
        return '[Custom Message]';
      case MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS:
        return '[Group event]';
      default:
        return '[Message]';
    }
  }

  Future<String?> _resolveAvatar(V2TimMessage message) async {
    final groupId = message.groupID;
    if (groupId != null && groupId.isNotEmpty) {
      // Group sender avatar — skip; rendering a per-sender avatar in a
      // group banner is more work than this initial pass should do.
      return null;
    }
    final userId = message.userID ?? message.sender;
    if (userId == null || userId.isEmpty) return null;
    try {
      return await Prefs.getFriendAvatarPath(userId);
    } catch (e) {
      AppLogger.debug(
          '[NotificationMessageListener] avatar lookup failed for $userId: $e');
      return null;
    }
  }

  /// Test-only — does not unregister the SDK listener (no-op there is by
  /// design; see class-level comment).
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }

  /// Test-only — returns whether the listener has been added to the SDK.
  @visibleForTesting
  bool get registeredForTest => _registered;
}

/// Convenience hook: pulls the active FfiChatService off [FakeUIKit] when
/// the caller doesn't have a handle. Returns null if FakeUIKit hasn't been
/// started yet — callers should retry once the session is ready.
NotificationMessageListener? notificationListenerFromFakeUiKit() {
  final ffi = FakeUIKit.instance.im?.ffi;
  if (ffi == null) return null;
  return NotificationMessageListener.forService(ffi);
}
