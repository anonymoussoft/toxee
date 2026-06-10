// Regression gate for BUG-1: custom-elem message with non-JSON data must
// render a visible row on mobile (not a blank Container).
//
// Root cause: TencentCloudChatMessageRow.defaultBuilder (mobile code path)
// called json.decode(customElem.data) and returned Container() in the catch
// block, silently blanking any custom-elem message whose data is not valid
// JSON.  The fix makes the catch block fall through to the normal row layout
// (matching desktopBuilder, which has no custom-elem guard at all).
//
// This file gates:
//   (a) non-JSON custom-elem data renders visible content on mobile (not blank)
//   (b) the same fixture at desktop size also renders visible content
//       (symmetry check — desktop was never broken, but this confirms it stays)
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness helpers (deliberately duplicated — test files must not share private
// helpers; see CLAUDE.md harness facts).
// ---------------------------------------------------------------------------

Widget _ceLocalized({required Widget child}) {
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

/// Minimal recording SDK platform — serves the fixture history and stubs the
/// required SDK calls.  Duplicated from the mobile/desktop test harnesses (no
/// shared private imports).
class _CeRecordingSdkPlatform extends TencentCloudChatSdkPlatform {
  _CeRecordingSdkPlatform({required this.history});

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
    final list = lastMsgID == null ? List<V2TimMessage>.of(history) : <V2TimMessage>[];
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
        userID: 'ce_friend',
        showName: 'CE Friend',
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
  Future<V2TimValueCallback<V2TimMsgCreateInfoResult>> createTextMessage({
    required String text,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(
        id: 'ce_created_0',
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
        sender: 'ce_self',
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
      'ce_uikit_listener';

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

/// Build the fixture history with:
///   ce_nonjson — a custom-elem whose data is plain non-JSON ('plain-not-json')
///   ce_json    — a custom-elem with valid JSON data (control: was never broken)
///   ce_text    — a plain text bubble to anchor the list
List<V2TimMessage> _buildCeFixtureHistory() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return [
    V2TimMessage(
      msgID: 'ce_text',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: 'anchor text'),
      isSelf: false,
      timestamp: now - 3600,
      sender: 'ce_friend',
      nickName: 'CE Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'ce_json',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
      // Valid JSON — never triggered the bug; used as symmetry control.
      customElem: V2TimCustomElem(data: '{"type":"ce_control"}'),
      isSelf: false,
      timestamp: now - 300,
      sender: 'ce_friend',
      nickName: 'CE Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'ce_nonjson',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
      // NON-JSON data — this is the exact data shape that triggered the blank
      // row bug.  Before the fix, defaultBuilder's catch block returned
      // Container() here.  After the fix it falls through to the standard row
      // layout which calls handleCustomMessage() → Text('[Custom]').
      customElem: V2TimCustomElem(data: 'plain-not-json'),
      isSelf: false,
      timestamp: now - 30,
      sender: 'ce_friend',
      nickName: 'CE Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    // VALID JSON but NOT a Map — these also blanked before the fix, because
    // the old code cast the decoded value to Map<String, dynamic> before
    // reading customerServicePlugin, and the cast threw inside the same
    // catch → Container() block (codex review finding, 2026-06-10).
    for (final (i, data) in const [
      ('ce_json_array', '[]'),
      ('ce_json_string', '"x"'),
      ('ce_json_number', '42'),
    ].indexed)
      V2TimMessage(
        msgID: data.$1,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
        customElem: V2TimCustomElem(data: data.$2),
        isSelf: false,
        timestamp: now - 20 + i,
        sender: 'ce_friend',
        nickName: 'CE Friend',
      )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  ];
}

/// Every custom-elem fixture row that used to blank on mobile before the fix.
const List<String> _ceFormerlyBlankIds = [
  'ce_nonjson',
  'ce_json_array',
  'ce_json_string',
  'ce_json_number',
];

/// Mounts the REAL chat page at [size] with [screenType].
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
      userFullInfo: V2TimUserFullInfo(userID: 'ce_self', nickName: 'CeSelf'));
  data.conversation.conversationList = [
    V2TimConversation(
        conversationID: 'c2c_ce_friend',
        type: 1,
        userID: 'ce_friend',
        showName: 'CE Friend'),
  ];
  data.messageData.messageListMap = {};
  addTearDown(() {
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
    data.basic.usedComponents = [];
  });

  final platform = _CeRecordingSdkPlatform(history: _buildCeFixtureHistory());
  final oldPlatform = TencentCloudChatSdkPlatform.instance;
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

  await tester.pumpWidget(
    _ceLocalized(
      child: TencentCloudChatMessage(
        options: TencentCloudChatMessageOptions(userID: 'ce_friend'),
        config: TencentCloudChatMessageConfig(),
        builders: TencentCloudChatMessageBuilders(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();
}

Finder _ceRowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  testWidgets(
    'BUG-1 regression mobile: non-JSON custom-elem data renders visible content, not a blank row',
    (tester) async {
      await _pumpChatAtSize(
        tester,
        size: const Size(400, 800),
        screenType: DeviceScreenType.mobile,
      );

      // The anchor text bubble and the row container must both be present.
      expect(_ceRowItem('ce_text'), findsOneWidget,
          reason: 'anchor text bubble must render as sanity check');

      // The row must have visible content — specifically the [Custom] fallback
      // text rendered by TencentCloudChatMessageCustom.defaultBuilder via
      // handleCustomMessage().  find.text('[Custom]') will return the TEXT
      // widgets inside the visible custom bubbles.
      final customLabels = find.text('[Custom]', skipOffstage: false);
      expect(customLabels, findsWidgets,
          reason:
              'custom-elem rows must render [Custom] fallback text (not be blank)');

      // Every formerly-blank shape (non-JSON, JSON array/string/number) must
      // mount with a non-zero render size — a blank Container() would have
      // zero height once the parent imposes no forced size.
      for (final id in _ceFormerlyBlankIds) {
        expect(_ceRowItem(id), findsOneWidget,
            reason: '$id row must mount in the list (not be blank)');
        final rowElement = tester.element(_ceRowItem(id));
        final renderBox = rowElement.renderObject as RenderBox;
        expect(renderBox.size.height, greaterThan(0),
            reason: '$id row must have non-zero height (not blank)');
      }

      // No render overflow exceptions.
      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions after mounting non-JSON custom-elem');
    },
  );

  testWidgets(
    'BUG-1 regression desktop: non-JSON custom-elem data renders visible content (symmetry check)',
    (tester) async {
      await _pumpChatAtSize(
        tester,
        size: const Size(1400, 900),
        screenType: DeviceScreenType.desktop,
      );

      expect(_ceRowItem('ce_text'), findsOneWidget,
          reason: 'anchor text bubble must render on desktop too');

      final customLabels = find.text('[Custom]', skipOffstage: false);
      expect(customLabels, findsWidgets,
          reason: 'custom-elem rows must render [Custom] text on desktop');

      // Desktop never had the bug, but every shape must keep rendering there
      // too (symmetry: the fix must not regress the desktop path).
      for (final id in _ceFormerlyBlankIds) {
        expect(_ceRowItem(id), findsOneWidget,
            reason: '$id row must mount on desktop');
        final rowElement = tester.element(_ceRowItem(id));
        final renderBox = rowElement.renderObject as RenderBox;
        expect(renderBox.size.height, greaterThan(0),
            reason: '$id row must have non-zero height on desktop');
      }

      expect(tester.takeException(), isNull,
          reason: 'no layout exceptions after mounting non-JSON custom-elem on desktop');
    },
  );
}
