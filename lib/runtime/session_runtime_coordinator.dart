import 'dart:async';

import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_method_channel.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';

import '../adapters/conversation_manager_adapter.dart';
import '../adapters/event_bus_adapter.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../util/logger.dart';

enum SessionRuntimeState { notStarted, starting, started, disposed }

/// Coordinates session-level runtime: FakeUIKit, TencentCloudChatSdkPlatform,
/// and CallServiceManager. [ensureInitialized] is idempotent; [disposeRuntime]
/// is called on teardown (e.g. from AccountService).
class SessionRuntimeCoordinator {
  SessionRuntimeCoordinator({required this.service});

  final FfiChatService service;

  static SessionRuntimeState _state = SessionRuntimeState.notStarted;
  static Future<void>? _initializing;

  /// Whether the [BinaryReplacementHistoryHook] has been installed by this
  /// coordinator for the current session. Reset by [disposeRuntime] so a
  /// post-logout re-init reinstalls the hook against the new selfId.
  static bool _hookInstalled = false;

  /// Pending one-shot subscription that waits for selfId to become available
  /// (post-login) before installing the hook. Cancelled by [disposeRuntime].
  static StreamSubscription<bool>? _pendingHookSelfIdSub;

  static SessionRuntimeState get state => _state;

  /// Initializes session runtime if not already started. Idempotent.
  /// Concurrent callers await the same in-flight initialization.
  /// After [disposeRuntime] (e.g. logout/account switch), calling this again
  /// re-initializes the runtime for the new session.
  Future<void> ensureInitialized() async {
    if (_state == SessionRuntimeState.started) return;
    final inFlight = _initializing;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    // Allow re-initialization after dispose (post-logout / account-switch).
    if (_state == SessionRuntimeState.disposed) {
      AppLogger.debug('[SessionRuntimeCoordinator] Re-initializing after teardown');
    }

    _state = SessionRuntimeState.starting;
    final completer = Completer<void>();
    _initializing = completer.future;

    try {
      if (!FakeUIKit.instance.isStarted) {
        // Async since A7: awaits initial pinned-conversation read so the
        // platform bridge installed below never sees an empty pinned set.
        await FakeUIKit.instance.startWithFfi(service);
      }

      if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
        final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
        final conversationManagerAdapter = ConversationManagerAdapter(
          FakeUIKit.instance.conversationManager!,
        );
        final platform = Tim2ToxSdkPlatform(
          ffiService: service,
          eventBusProvider: eventBusAdapter,
          conversationManagerProvider: conversationManagerAdapter,
        );
        TencentCloudChatSdkPlatform.instance = platform;
        platform.onGroupMessageReceivedForUnread = (groupId) {
          if (groupId != null && groupId.isNotEmpty) {
            service.incrementGroupUnread(groupId);
          }
          FakeUIKit.instance.im?.refreshConversations();
          FakeUIKit.instance.im?.refreshUnreadTotal();
        };
        AppLogger.debug('[SessionRuntimeCoordinator] Set TencentCloudChatSdkPlatform to Tim2ToxSdkPlatform');
      }

      await FakeUIKit.instance.callServiceManager?.initialize();
      UikitDataFacade.setUseCallKit(true);

      // Install the binary-replacement history hook in the same atomic init
      // block as the platform, so the "platform installed but hook not yet
      // installed" window (where FFI-path messages could land in persistence
      // without UIKit listener mediation) cannot exist.
      _installBinaryReplacementHistoryHook();

      _state = SessionRuntimeState.started;
      completer.complete();
    } catch (e, st) {
      _state = SessionRuntimeState.notStarted;
      completer.completeError(e, st);
      rethrow;
    } finally {
      _initializing = null;
    }
    // callSystemReady is set by FakeUIKit.startWithFfi() via addPostFrameCallback to avoid
    // "setState() or markNeedsBuild() called during build".
  }

  /// Call on session teardown (e.g. logout). Resets runtime state.
  static Future<void> disposeRuntime() async {
    if (_state == SessionRuntimeState.disposed) return;
    _state = SessionRuntimeState.disposed;

    // BinaryReplacementHistoryHook intentionally exposes no public uninstall
    // API: its static `_persistence`/`_selfId` are overwritten by the next
    // `initialize`, and an in-flight `saveMessage` from the old session is
    // fenced by its generation counter (see X8 regression test). We therefore
    // only reset our own bookkeeping here so a subsequent `ensureInitialized`
    // re-installs the hook against the new session's persistence + selfId.
    await _pendingHookSelfIdSub?.cancel();
    _pendingHookSelfIdSub = null;
    _hookInstalled = false;

    FakeUIKit.instance.dispose();

    final platform = TencentCloudChatSdkPlatform.instance;
    if (platform is Tim2ToxSdkPlatform) {
      platform.dispose();
      TencentCloudChatSdkPlatform.instance = MethodChannelTencentCloudChatSdk();
    }
  }

  /// Installs the binary-replacement history hook against the current
  /// session's persistence + selfId. Idempotent within a session via
  /// [_hookInstalled]; reset by [disposeRuntime] so a fresh
  /// [ensureInitialized] re-installs against the new account.
  ///
  /// If selfId is not yet known (e.g. invoked before login completes), we
  /// arm a one-shot listener on [FfiChatService.connectionStatusStream] and
  /// install when the first connected event with a non-empty selfId arrives.
  void _installBinaryReplacementHistoryHook() {
    if (_hookInstalled) return;
    try {
      final selfId = service.selfId;
      if (selfId.isEmpty) {
        AppLogger.debug(
            '[SessionRuntimeCoordinator] selfId not available yet, deferring hook install');
        _pendingHookSelfIdSub?.cancel();
        _pendingHookSelfIdSub = service.connectionStatusStream
            .where((connected) => connected && service.selfId.isNotEmpty)
            .take(1)
            .listen((_) {
          _setupBinaryReplacementHistoryHook(service.selfId);
        });
        return;
      }
      _setupBinaryReplacementHistoryHook(selfId);
    } catch (e, st) {
      AppLogger.logError(
          '[SessionRuntimeCoordinator] Error installing history hook: $e',
          e,
          st);
    }
  }

  void _setupBinaryReplacementHistoryHook(String selfId) {
    if (_hookInstalled) return;
    try {
      BinaryReplacementHistoryHook.initialize(
          service.messageHistoryPersistence, selfId);

      final currentListeners =
          TIMMessageManager.instance.v2TimAdvancedMsgListenerList;
      if (currentListeners.isNotEmpty) {
        final originalListener = currentListeners.first;
        final wrappedListener =
            BinaryReplacementHistoryHook.wrapListener(originalListener);
        TIMMessageManager.instance
            .removeAdvancedMsgListener(listener: originalListener);
        TIMMessageManager.instance.addAdvancedMsgListener(wrappedListener);
        _hookInstalled = true;
        AppLogger.debug(
            '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook installed (wrapped existing listener)');
      } else {
        final listener = V2TimAdvancedMsgListener(
          onRecvNewMessage: (V2TimMessage message) {
            BinaryReplacementHistoryHook.saveMessage(message);
          },
        );
        TIMMessageManager.instance.addAdvancedMsgListener(listener);
        _hookInstalled = true;
        AppLogger.debug(
            '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook installed (new listener)');
      }
    } catch (e, st) {
      AppLogger.logError(
          '[SessionRuntimeCoordinator] Error setting up history hook: $e',
          e,
          st);
    }
  }
}
