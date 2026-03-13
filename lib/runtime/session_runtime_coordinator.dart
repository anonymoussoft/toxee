import 'dart:async';

import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_method_channel.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';

import '../adapters/conversation_manager_adapter.dart';
import '../adapters/event_bus_adapter.dart';
import '../sdk_fake/fake_uikit_core.dart';
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
        FakeUIKit.instance.startWithFfi(service);
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
      TencentCloudChat.instance.dataInstance.basic.useCallKit = true;

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

    FakeUIKit.instance.dispose();

    final platform = TencentCloudChatSdkPlatform.instance;
    if (platform is Tim2ToxSdkPlatform) {
      platform.dispose();
      TencentCloudChatSdkPlatform.instance = MethodChannelTencentCloudChatSdk();
    }
  }
}
