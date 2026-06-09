// L1 unit test for S83 — the MUTE SUPPRESSION DECISION (the half the Fixture C
// `run_fixture_c_mute.sh` gate does NOT cover: that gate proves the mute STATE
// persists as recvOpt=2; this proves the NotificationMessageListener actually
// SUPPRESSES an inbound notification for a muted sender).
//
// `_shouldSuppress` (notification_message_listener.dart:183) is the contract:
// for a muted sender it must return true (no banner). The mute lookup it trusts
// first is the synchronous `C2CRecvOptCache.isMuted(sender)` projection (the
// same cache the recvOpt Fixture C gate writes). We drive it through the
// `@visibleForTesting` `debugShouldSuppress` seam over a stub FfiChatService so
// the self/blocked/active-conversation guards are all known-not-firing and the
// MUTE branch is the only thing under test.
//
// NOTE: constructing `FfiChatService` (`: super()`) opens the tim2tox FFI dylib
// + MessageHistoryPersistence, same as test/ui/add_friend_guards_test.dart — so
// this loads the native lib and is not a pure no-native test.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/notifications/notification_message_listener.dart';
import 'package:toxee/sdk_fake/c2c_recv_opt_cache.dart';
import 'package:toxee/sdk_fake/uikit_data_facade.dart';

// Distinct 64-char (normalized) ids so sender != self and neither is blocked.
final String _peer = 'C' * 64;
final String _self = 'D' * 64;

class _StubService extends FfiChatService {
  _StubService() : super();

  // The suppression decision reads exactly these two off the service.
  @override
  String get selfId => _self;

  @override
  bool isBlocked(String peerId) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // V2TimMessage construction reaches into the SDK native binding (getServerTime
  // for a default seq); point it at the tim2tox lib the stub's super() loads
  // (process-global, matches test/ui/chat_core_real_ui_test.dart).
  setNativeLibraryName('tim2tox_ffi');

  // Constructing FfiChatService / the listener may touch SystemChannels; mock
  // the platform channel (JSONMethodCodec) so it never hits a real plugin.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  late _StubService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async => null);
    service = _StubService();
    // No active conversation → the foreground/active-conversation guard cannot
    // fire, isolating the mute branch.
    UikitDataFacade.currentConversation = null;
    C2CRecvOptCache.debugClear();
  });

  tearDown(() {
    C2CRecvOptCache.debugClear();
    UikitDataFacade.currentConversation = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });

  V2TimMessage inbound(String sender) => V2TimMessage(
        msgID: 'mute-test',
        isSelf: false,
        sender: sender,
        userID: sender,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: 'ping'),
        timestamp: 1700000000,
      );

  group('S83 mute suppression decision', () {
    test('a MUTED sender (recvOpt=2) suppresses the inbound notification', () {
      C2CRecvOptCache.setLocal(_peer, 2); // recvOpt != 0 == muted
      expect(C2CRecvOptCache.isMuted(_peer), isTrue,
          reason: 'precondition: the cache reports the sender muted');

      expect(NotificationMessageListener.debugShouldSuppressFor(service, inbound(_peer)), isTrue,
          reason:
              'a muted conversation must NOT ring a notification (the mute '
              'branch of _shouldSuppress must return true)');
    });

    test('an UNMUTED sender does NOT suppress (no other guard fires)', () {
      expect(C2CRecvOptCache.isMuted(_peer), isFalse,
          reason: 'precondition: the sender is not muted');

      // Self=false, sender != selfId, not blocked, plain text (no __revoke__),
      // no active conversation → the ONLY branch that could suppress is mute,
      // and it is off, so the decision must be "notify".
      expect(NotificationMessageListener.debugShouldSuppressFor(service, inbound(_peer)), isFalse,
          reason:
              'an unmuted, non-self, non-blocked, non-active inbound must '
              'produce a notification (decision = do NOT suppress)');
    });

    test('un-muting flips the decision from suppress back to notify', () {
      C2CRecvOptCache.setLocal(_peer, 2);
      expect(NotificationMessageListener.debugShouldSuppressFor(service, inbound(_peer)), isTrue);

      // recvOpt back to 0 (un-mute) — the same sender must now notify.
      C2CRecvOptCache.setLocal(_peer, 0);
      expect(C2CRecvOptCache.isMuted(_peer), isFalse);
      expect(NotificationMessageListener.debugShouldSuppressFor(service, inbound(_peer)), isFalse,
          reason: 'clearing the mute must re-enable notifications');
    });
  });
}
