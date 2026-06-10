// Real-UI gate for the UI halves of S13 (resend a failed outbound message)
// and S25 (offline-queued / pending outbound state).
//
// This pumps the REAL TencentCloudChatMessage list and drives the REAL
// production status-indicator + resend wiring in the UIKit fork:
//
//   * pending (SENDING) outbound bubble  -> messageStatusIndicator() renders
//     _renderSendingStatus() (a CircularProgressIndicator in-flight spinner)
//     — tencent_cloud_chat_message_item.dart:89-99,192-194.
//   * failed (SEND_FAIL) outbound bubble -> messageStatusIndicator() renders
//     _renderFailedStatus() (a Semantics(label:'Retry') wrapping the
//     Icons.refresh affordance + Icons.error glyph)
//     — tencent_cloud_chat_message_item.dart:134-166,196-198.
//   * tapping the refresh affordance fires widget.methods.onResendMessage
//     (item.dart:175-179). In production the row container wires that callback
//     to _resendMessage -> dataProvider.resendMessage(message)
//     -> _sendMessage(isResend:true) -> messageSDK.reSendMessage(msgID:)
//     -> platform.reSendMessage(msgID:) (row_container.dart:274-275,548;
//      separate_data.dart:1085-1091,945-962; message_sdk.dart:331-332;
//      data_tools.dart:219-232 — the isResend branch picks reSendMessage, never
//      a fresh sendMessage). The widget-layer gate captures at the onResendMessage
//      seam (the real production callback) and asserts the SAME failed msgID is
//      re-dispatched; the deeper SDK chain above is production wiring this tap
//      engages but is proven for network-arrival at the L3 layer (see S13.md).
//   * when the resend succeeds (the message flips to SEND_SUCC for the same
//     msgID), production sets messageData.messageNeedUpdate (data_tools.dart:
//     240-251) and the list-view container replaces the in-list message,
//     re-rendering the bubble without the failure affordance
//     (message_list_view_container.dart:60-122). We mirror that in-place
//     replacement by re-pumping the same bubble at SEND_SUCC, and assert 'Retry'
//     affordance is gone afterwards.
//
// Both mobile (400x800) and desktop (1400x900) sizes are exercised so the
// two bubble layout branches (text bubble lines 196 and 261, both gated on
// `if (sentFromSelf) messageStatusIndicator()`) are covered.
//
// S13 names TWO retry paths: V1 (offline-queue auto-drain, which has NO UI
// affordance — the refresh glyph is SEND_FAIL-gated only, per S13 Notes) and
// V2 (the SEND_FAIL tap-to-resend affordance). Only V2 is widget-reachable;
// the V1 auto-drain is a network/queue flow with no tappable surface (proven
// at the L3 layer instead). This file covers V2 (the tap-to-resend path) plus
// the pending-bubble rendering that both S13 and S25 rely on.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_text.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness helpers (deliberately duplicated — test files must not share private
// helpers; see CLAUDE.md harness facts). Adapted from
// test/ui/chat/custom_elem_mobile_render_regression_test.dart.
// ---------------------------------------------------------------------------

Widget _prLocalized({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return child;
        },
      ),
    ),
  );
}

/// Minimal SDK platform — serves the seeded fixture history and stubs the SDK
/// calls the message component makes during render (reSendMessage / sendMessage
/// are benign code-0 stubs). The whole-list render tests never tap (the
/// FlutterListView rows are not hit-testable in WidgetTester), so this platform
/// only needs to SERVE the history; the tap→resend path is exercised on the
/// real bubble widget directly via [_pumpRealBubble], which records the real
/// onResendMessage callback itself.
class _PrHistorySdkPlatform extends TencentCloudChatSdkPlatform {
  _PrHistorySdkPlatform({required this.history});

  final List<V2TimMessage> history;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<V2TimMessageListResult>> getHistoryMessageListV2({
    int getType = HistoryMessageGetType.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    final list =
        lastMsgID == null ? List<V2TimMessage>.of(history) : <V2TimMessage>[];
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessageListResult(isFinished: true, messageList: list),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimConversation>> getConversation({
    required String conversationID,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimConversation(
        conversationID: conversationID,
        type: 1,
        userID: 'pr_friend',
        showName: 'PR Friend',
      ),
    );
  }

  @override
  Future<V2TimCallback> cleanConversationUnreadMessageCount({
    required String conversationID,
    required int cleanTimestamp,
    required int cleanSequence,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> sendMessageReadReceipts({
    List<String>? messageIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> reSendMessage({
    required String msgID,
    bool onlineUserOnly = false,
    Object? webMessageInstatnce,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessage(
        msgID: msgID,
        id: msgID,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        isSelf: true,
        sender: 'pr_self',
      )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    );
  }

  @override
  Future<V2TimValueCallback<V2TimMsgCreateInfoResult>> createTextMessage({
    required String text,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(
        id: 'pr_created_0',
        messageInfo: V2TimMessage(
          elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          textElem: V2TimTextElem(text: text),
          isSelf: true,
        ),
      ),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    String? id,
    required String receiver,
    required String groupID,
    int priority = 0,
    bool onlineUserOnly = false,
    bool? needReadReceipt,
    bool? isExcludedFromUnreadCount,
    bool? isExcludedFromLastMessage,
    bool? isSupportMessageExtension,
    bool? isExcludedFromContentModeration,
    Map<String, dynamic>? offlinePushInfo,
    String? cloudCustomData,
    String? localCustomData,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessage(
        msgID: id,
        id: id,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        isSelf: true,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        sender: 'pr_self',
      )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    );
  }

  @override
  Future<V2TimCallback> deleteMessages({
    List<String>? msgIDs,
    List<dynamic>? webMessageInstanceList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimValueCallback<List<V2TimUserFullInfo>>> getUsersInfo({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: userIDList.map((u) => V2TimUserFullInfo(userID: u)).toList(),
    );
  }

  @override
  Future<V2TimValueCallback<List<V2TimFriendInfoResult>>> getFriendsInfo({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(code: 0, desc: 'ok', data: const []);
  }

  @override
  Future<V2TimValueCallback<List<V2TimUserStatus>>> getUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(code: 0, desc: 'ok', data: const []);
  }

  @override
  Future<V2TimCallback> subscribeUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> unsubscribeUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  String addUIKitListener({required V2TimUIKitListener listener}) =>
      'pr_uikit_listener';

  @override
  void removeUIKitListener({String? uuid}) {}

  @override
  Future<V2TimCallback> setConversationDraft({
    required String conversationID,
    String? draftText,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

const String _pendingMsgId = 'pr_pending';
const String _failedMsgId = 'pr_failed';

/// Build the fixture history with three OUTGOING (isSelf:true) text bubbles:
///   pr_succ    — a delivered bubble (anchor / control; renders the done tick)
///   pr_pending — a SENDING bubble (in-flight spinner)
///   pr_failed  — a SEND_FAIL bubble (refresh + error affordance)
List<V2TimMessage> _buildPendingResendFixtureHistory() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return [
    V2TimMessage(
      msgID: 'pr_succ',
      id: 'pr_succ',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: 'delivered anchor'),
      isSelf: true,
      timestamp: now - 3600,
      sender: 'pr_self',
      nickName: 'PR Self',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: _pendingMsgId,
      id: _pendingMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: 'still sending'),
      isSelf: true,
      timestamp: now - 60,
      sender: 'pr_self',
      nickName: 'PR Self',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SENDING,
    V2TimMessage(
      msgID: _failedMsgId,
      id: _failedMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: 'this one failed'),
      isSelf: true,
      timestamp: now - 30,
      sender: 'pr_self',
      nickName: 'PR Self',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
  ];
}

/// Mounts the REAL chat page (whole TencentCloudChatMessage list) at
/// [size]/[screenType] with the seeded pending+failed history. Used by the
/// RENDER assertions (a)(b); the tap path uses [_pumpRealBubble] instead.
Future<void> _pumpChatAtSize(
  WidgetTester tester, {
  required Size size,
  required DeviceScreenType screenType,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = screenType;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  data.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'pr_self', nickName: 'PrSelf'));
  data.conversation.conversationList = [
    V2TimConversation(
        conversationID: 'c2c_pr_friend',
        type: 1,
        userID: 'pr_friend',
        showName: 'PR Friend'),
  ];
  data.messageData.messageListMap = {};
  addTearDown(() {
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
    data.basic.usedComponents = [];
  });

  final platform =
      _PrHistorySdkPlatform(history: _buildPendingResendFixtureHistory());
  final oldPlatform = TencentCloudChatSdkPlatform.instance;
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

  await tester.pumpWidget(
    _prLocalized(
      child: TencentCloudChatMessage(
        options: TencentCloudChatMessageOptions(userID: 'pr_friend'),
        config: TencentCloudChatMessageConfig(),
        builders: TencentCloudChatMessageBuilders(),
      ),
    ),
  );
  // NOTE: do NOT pumpAndSettle here — the SENDING bubble renders a
  // CircularProgressIndicator (item.dart:_renderSendingStatus) which animates
  // forever, so pumpAndSettle would time out. Use bounded pumps to let the
  // async history load + list build complete.
  await _settleBounded(tester);
}

/// Bounded settle for a tree that contains a perpetual spinner: pump a fixed
/// number of frames with real-time gaps so async history loads + setState
/// rebuilds flush, without waiting for the never-idle CircularProgressIndicator.
Future<void> _settleBounded(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

// ---------------------------------------------------------------------------
// Direct-bubble harness for the TAP/resend half of S13.
//
// The whole-list path above proves the indicators RENDER, but the chat's
// FlutterListView (flutter_list_view, keepPosition+reverse, firstItemAlign.end)
// pre-measures rows OFFSTAGE in WidgetTester and never realizes them on-stage,
// so its refresh glyph is not hit-testable. To drive the REAL resend handler
// through a REAL tap, we mount the REAL production bubble widget
// (TencentCloudChatMessageText, whose state is TencentCloudChatMessageState —
// the same class that owns messageStatusIndicator()/_renderFailedStatus() and
// the onTap -> widget.methods.onResendMessage wiring) directly. No production
// logic is re-implemented; only the real row-container plumbing
// (MessageItemBuilderData/Methods) is supplied, exactly as
// tencent_cloud_chat_message_row_container.dart:486-549 builds it.
// ---------------------------------------------------------------------------

/// Builds a self text message at [status].
V2TimMessage _selfTextMessage(
  String msgID,
  String text,
  int status,
) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return V2TimMessage(
    msgID: msgID,
    id: msgID,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: text),
    isSelf: true,
    timestamp: now - 30,
    sender: 'pr_self',
    nickName: 'PR Self',
  )..status = status;
}

MessageItemBuilderData _bubbleData(V2TimMessage message, double rowWidth) =>
    MessageItemBuilderData(
      message: message,
      userID: 'pr_friend',
      altText: '[message]',
      enableParseMarkdown: false,
      showMessageStatusIndicator: true,
      showMessageTimeIndicator: true,
      shouldBeHighlighted: false,
      showMessageSenderName: false,
      messageRowWidth: rowWidth,
      renderOnMenuPreview: false,
      inSelectMode: false,
      inMergerMessagePreviewMode: false,
      hasStickerPlugin: false,
    );

/// Mounts a single REAL text bubble at [size]/[screenType] and returns a
/// `resendCalls` list the real onResendMessage handler appends to. The
/// returned function re-pumps the SAME bubble with a SEND_SUCC message,
/// mirroring the production list-view's in-place status replacement
/// (message_list_view_container.dart:60-122) so coverage (d) drives the real
/// re-render, not a synthetic state mutation.
Future<({List<String> resendCalls, Future<void> Function() markSucceeded})>
    _pumpRealBubble(
  WidgetTester tester, {
  required Size size,
  required DeviceScreenType screenType,
  required V2TimMessage message,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = screenType;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'pr_self', nickName: 'PrSelf'));

  final resendCalls = <String>[];

  MessageItemBuilderMethods buildMethods() => MessageItemBuilderMethods(
        clearHighlightFunc: () {},
        triggerLinkTappedEvent: (_) {},
        setMessageTextWithMentions: (
                {required String messageText,
                required List<String> groupMembersNeedToMention}) {},
        // THE production resend hook (row_container.dart:548 wires _resendMessage
        // here). We record the msgID instead of calling the SDK so the test is
        // hermetic, but the path that reaches this callback is 100% production.
        onResendMessage: () => resendCalls.add(message.msgID ?? ''),
      );

  Future<void> pump(V2TimMessage m) async {
    await tester.pumpWidget(
      _prLocalized(
        // Give the bubble the full viewport width so its self-aligned Row
        // (bubble + timestamp + status indicator) has room — outside the real
        // list there is no parent width, which would otherwise overflow.
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            child: TencentCloudChatMessageText(
              data: _bubbleData(m, size.width),
              methods: buildMethods(),
            ),
          ),
        ),
      ),
    );
    if (m.status == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      // perpetual spinner — bounded pump only
      await _settleBounded(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  await pump(message);

  Future<void> markSucceeded() async {
    // Mirror the production list-view in-place replacement: same msgID, now
    // SEND_SUCC -> the bubble must drop the failure affordance.
    await pump(_selfTextMessage(
      message.msgID ?? '',
      message.textElem?.text ?? 'resent',
      MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    ));
  }

  return (resendCalls: resendCalls, markSucceeded: markSucceeded);
}

Finder _prRowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

/// The in-flight spinner rendered by _renderSendingStatus().
Finder _prSendingIndicator() =>
    find.byType(CircularProgressIndicator, skipOffstage: false);

/// The SEND_FAIL retry affordance: a Semantics(button:true,label:'Retry')
/// wrapping the Icons.refresh glyph (item.dart:140-143).
Finder _prRetryAffordance() => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label == 'Retry') &&
          (w.properties.button ?? false),
      skipOffstage: false,
    );

/// The refresh glyph itself (Icons.refresh) — unique to the SEND_FAIL retry
/// affordance in this fixture. find.byIcon must be told skipOffstage:false so
/// it matches even when the bubble row is offstage in the list path.
Finder _prRefreshGlyph() => find.byIcon(Icons.refresh, skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  // (a) pending outbound message renders the real in-flight indicator.
  testWidgets(
    'S25/S13 mobile: a pending (SENDING) outbound bubble renders the in-flight spinner',
    (tester) async {
      await _pumpChatAtSize(
        tester,
        size: const Size(400, 800),
        screenType: DeviceScreenType.mobile,
      );

      expect(_prRowItem(_pendingMsgId), findsOneWidget,
          reason: 'the pending outbound bubble must mount in the list');
      expect(_prSendingIndicator(), findsWidgets,
          reason:
              'a SENDING outbound bubble must render the in-flight spinner '
              '(_renderSendingStatus CircularProgressIndicator)');

      // The pending bubble exposes NO retry affordance (S13 Notes: the refresh
      // glyph is SEND_FAIL-gated only) — but the SEPARATE failed fixture row
      // does, so we only assert the pending row itself stays spinner-only by
      // confirming the spinner is present. (Retry-presence is asserted in the
      // failed-bubble test below.)
      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions rendering the pending bubble');
    },
  );

  // (b) a FAILED outbound message renders the real failure affordance.
  testWidgets(
    'S13 mobile: a failed (SEND_FAIL) outbound bubble renders the real Retry affordance',
    (tester) async {
      await _pumpChatAtSize(
        tester,
        size: const Size(400, 800),
        screenType: DeviceScreenType.mobile,
      );

      expect(_prRowItem(_failedMsgId), findsOneWidget,
          reason: 'the failed outbound bubble must mount in the list');
      expect(_prRetryAffordance(), findsOneWidget,
          reason:
              'a SEND_FAIL outbound bubble must render the Retry Semantics '
              'affordance (_renderFailedStatus)');
      expect(_prRefreshGlyph(), findsOneWidget,
          reason: 'the Retry affordance must contain the Icons.refresh glyph');

      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions rendering the failed bubble');
    },
  );

  // (c) + (d) tapping the failure affordance drives the PRODUCTION resend path,
  // and after the resend succeeds the bubble leaves the failed state. Driven on
  // the REAL production bubble widget (the list's FlutterListView keeps rows
  // offstage/non-hittable in WidgetTester — see _pumpRealBubble docs).
  testWidgets(
    'S13 mobile: tapping the failed bubble re-dispatches the same message and clears the failed state',
    (tester) async {
      final failed = _selfTextMessage(
        _failedMsgId,
        'this one failed',
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      );
      final h = await _pumpRealBubble(
        tester,
        size: const Size(400, 800),
        screenType: DeviceScreenType.mobile,
        message: failed,
      );

      // Precondition: the failed bubble shows the real, tappable affordance.
      expect(_prRetryAffordance(), findsOneWidget,
          reason: 'precondition: the failed bubble shows the Retry affordance');
      expect(_prRefreshGlyph(), findsOneWidget,
          reason: 'precondition: the failed bubble shows the refresh glyph');
      expect(h.resendCalls, isEmpty,
          reason: 'precondition: no resend dispatched before the tap');

      // (c) Tap the real refresh affordance -> drives the production
      // onTap -> widget.methods.onResendMessage (item.dart:175-179).
      await tester.tap(_prRefreshGlyph());
      await _settleBounded(tester);

      expect(h.resendCalls, contains(_failedMsgId),
          reason:
              'tapping the failed bubble must drive onResendMessage for the '
              'same message (msgID: $_failedMsgId)');

      // (d) When the resend succeeds (same msgID flips to SEND_SUCC, exactly
      // what the production list-view replacement does), the bubble must drop
      // the failure affordance.
      await h.markSucceeded();

      expect(_prRetryAffordance(), findsNothing,
          reason:
              'after a successful resend the bubble must leave the failed '
              'state (Retry affordance gone)');
      expect(_prRefreshGlyph(), findsNothing,
          reason: 'the refresh glyph must be gone once the message succeeds');
      // The bubble text itself must still render (the message did not vanish).
      expect(find.text('this one failed', skipOffstage: false), findsOneWidget,
          reason: 'the resent bubble must remain, not disappear');

      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions after the resend flip');
    },
  );

  // (b) desktop render: the second bubble layout branch (desktopBuilder, text
  // bubble line 261) must render the failed Retry affordance on the REAL list.
  testWidgets(
    'S13/S25 desktop: pending spinner + failed Retry affordance render on the real list (symmetry)',
    (tester) async {
      await _pumpChatAtSize(
        tester,
        size: const Size(1400, 900),
        screenType: DeviceScreenType.desktop,
      );

      // (a) desktop pending spinner.
      expect(_prRowItem(_pendingMsgId), findsOneWidget,
          reason: 'pending bubble must mount on desktop');
      expect(_prSendingIndicator(), findsWidgets,
          reason: 'pending bubble must render the in-flight spinner on desktop');

      // (b) desktop failed affordance.
      expect(_prRowItem(_failedMsgId), findsOneWidget,
          reason: 'failed bubble must mount on desktop');
      expect(_prRetryAffordance(), findsOneWidget,
          reason: 'failed bubble must render the Retry affordance on desktop');
      expect(_prRefreshGlyph(), findsOneWidget,
          reason: 'failed bubble must show the refresh glyph on desktop');

      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions rendering the desktop bubbles');
    },
  );

  // (c) + (d) desktop resend: drive the REAL production bubble (desktopBuilder
  // branch) through a real tap and assert the same resend + failed-state clear.
  testWidgets(
    'S13 desktop: tapping the failed bubble re-dispatches and clears the failed state (desktopBuilder)',
    (tester) async {
      final failed = _selfTextMessage(
        _failedMsgId,
        'this one failed',
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      );
      final h = await _pumpRealBubble(
        tester,
        size: const Size(1400, 900),
        screenType: DeviceScreenType.desktop,
        message: failed,
      );

      expect(_prRefreshGlyph(), findsOneWidget,
          reason: 'precondition: desktop failed bubble shows the refresh glyph');

      await tester.tap(_prRefreshGlyph());
      await _settleBounded(tester);
      expect(h.resendCalls, contains(_failedMsgId),
          reason: 'desktop tap must drive onResendMessage for the same message');

      await h.markSucceeded();
      expect(_prRetryAffordance(), findsNothing,
          reason: 'desktop bubble must leave the failed state after resend');
      expect(_prRefreshGlyph(), findsNothing,
          reason: 'desktop refresh glyph must be gone once the message succeeds');
      // Positive guard: the bubble must still render (so findsNothing above is
      // not vacuously true on an empty/broken tree).
      expect(find.text('this one failed', skipOffstage: false), findsOneWidget,
          reason: 'the resent desktop bubble must remain, not disappear');

      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions on the desktop resend path');
    },
  );
}
