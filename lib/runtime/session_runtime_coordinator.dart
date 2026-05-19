import 'dart:async';

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

  /// Installs the binary-replacement history hook as a standalone, independent
  /// V2TimAdvancedMsgListener that persists every received/modified message
  /// exactly once. This listener does NOT wrap or replace any UIKit listener,
  /// so every other registered listener continues to receive callbacks
  /// unmolested. (Pre-H1 the coordinator wrapped `currentListeners.first` — a
  /// race-prone path that silenced any listener registered before the hook
  /// installed and silently let later listeners persist nothing.)
  ///
  /// M6: installation happens immediately, even if `selfId` is still empty,
  /// so no binary-replacement event can arrive before persistence coverage is
  /// in place. When selfId becomes known via the connection event, we call
  /// [BinaryReplacementHistoryHook.updateSelfId] to plug it in. Idempotent
  /// within a session via [_hookInstalled]; reset by [disposeRuntime].
  void _installBinaryReplacementHistoryHook() {
    if (_hookInstalled) return;
    try {
      // Always install immediately — passes a placeholder if selfId is not
      // yet known. The saveMessage path guards against an empty selfId
      // already (no isSelf can be resolved), so worst case is a single early
      // message gets dropped instead of mis-attributed.
      final selfId = service.selfId;
      BinaryReplacementHistoryHook.installStandalone(
          service.messageHistoryPersistence, selfId);
      _hookInstalled = true;
      AppLogger.debug(
          '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook installed (standalone, selfId=${selfId.isEmpty ? "<deferred>" : "<set>"})');

      if (selfId.isEmpty) {
        // Plug in the real selfId as soon as the first connected event with
        // a non-empty selfId arrives. We don't re-install the listener.
        _pendingHookSelfIdSub?.cancel();
        _pendingHookSelfIdSub = service.connectionStatusStream
            .where((connected) => connected && service.selfId.isNotEmpty)
            .take(1)
            .listen((_) {
          BinaryReplacementHistoryHook.updateSelfId(service.selfId);
          AppLogger.debug(
              '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook selfId updated');
        });
      }
    } catch (e, st) {
      AppLogger.logError(
          '[SessionRuntimeCoordinator] Error installing history hook: $e',
          e,
          st);
    }
  }
}
