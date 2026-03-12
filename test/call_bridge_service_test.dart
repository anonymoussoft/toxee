// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSignalingListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';

void main() {
  test(
      'registers outgoing signaling calls so they can be looked up and canceled',
      () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);

    bridge.registerOutgoingCall(
      inviteID: 'invite-1',
      inviter: 'self',
      invitee: 'friend-1',
      data: '{"type":"audio","audio":true,"video":false}',
      friendNumber: 7,
    );

    final info = bridge.getCallInfo('invite-1');
    expect(info, isNotNull);
    expect(info!.inviter, 'self');
    expect(info.inviteeList, const ['friend-1']);
    expect(info.friendNumber, 7);
    expect(info.state, CallState.calling);

    await bridge.endCall('invite-1');

    expect(sdk.cancelledInviteIds, const ['invite-1']);
    expect(av.endedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-1'), isNull);
  });

  test('does not send signaling invite when outgoing call preflight denies',
      () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);

    adapter.onBeforeOutgoingCall = (_, __) async => false;

    final handled = await adapter.handleCall(
      type: TYPE_VIDEO,
      userids: const ['friend-1'],
    );

    expect(handled, isFalse);
    expect(sdk.inviteCallCount, 0);
    expect(bridge.getCallInfo('invite-1'), isNull);
  });
}

class _FakeSdkPlatform extends TencentCloudChatSdkPlatform {
  V2TimSignalingListener? listener;
  final List<String> cancelledInviteIds = <String>[];
  int inviteCallCount = 0;

  @override
  Future<void> addSignalingListener({
    required V2TimSignalingListener listener,
  }) async {
    this.listener = listener;
  }

  @override
  Future<void> removeSignalingListener({
    V2TimSignalingListener? listener,
  }) async {
    if (this.listener == listener) {
      this.listener = null;
    }
  }

  @override
  Future<V2TimValueCallback<String>> invite({
    required String invitee,
    required String data,
    int timeout = 30,
    bool onlineUserOnly = false,
    offlinePushInfo,
  }) async {
    inviteCallCount++;
    return V2TimValueCallback<String>(code: 0, desc: 'ok', data: 'invite-1');
  }

  @override
  Future<V2TimCallback> cancel({
    required String inviteID,
    String? data,
  }) async {
    cancelledInviteIds.add(inviteID);
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> accept({
    required String inviteID,
    String? data,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> reject({
    required String inviteID,
    String? data,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

class _FakeAvBackend implements CallAvBackend {
  final List<int> endedFriendNumbers = <int>[];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> answerCall(
    int friendNumber, {
    int audioBitRate = 64000,
    int videoBitRate = 5000000,
  }) async {
    return true;
  }

  @override
  Future<bool> endCall(int friendNumber) async {
    endedFriendNumbers.add(friendNumber);
    return true;
  }

  @override
  Future<bool> muteAudio(int friendNumber, bool mute) async => true;

  @override
  Future<bool> muteVideo(int friendNumber, bool hide) async => true;

  @override
  int getFriendNumberByUserId(String userId) => 7;

  @override
  Future<bool> startCall(
    int friendNumber, {
    int audioBitRate = 48,
    int videoBitRate = 5000,
  }) async {
    return true;
  }
}
