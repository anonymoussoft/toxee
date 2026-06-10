// Real-UI widget gates for the MESSAGE-bubble action menu on MOBILE
// (S15 surface via long-press, S16 copy, S17 forward presence, S18 reply,
// S15 delete leg) — the mobile twin of message_actions_menu_real_ui_test.dart.
//
// The REAL production page (TencentCloudChatMessage) is mounted at a 400x800
// mobile viewport with DeviceScreenType.mobile, so the fork's defaultBuilder
// (GestureDetector.onLongPress + overlay menu) is exercised instead of the
// desktop Listener path.  Every interaction drives the real production widgets.
//
// GROUND TRUTH (verified against the fork, 2026-06-10):
//   • Text-message mobile menu: Copy / Forward / Delete (no Reply, no Recall
//     for received; Recall added for a fresh self message inside the window).
//     multiSelect is stripped by the container (L537-612 tencent_cloud_chat_
//     message_item_with_menu_container.dart).
//   • Reply IS offered for quotable non-text elem types (custom); the test
//     exercises the real Reply item on the fixture custom-elem bubble.
//   • Forward on mobile opens a ModalBottomSheet (showModalBottomSheet) rather
//     than the TencentCloudChatDesktopPopup overlay used on desktop.  The test
//     verifies the forward menu item is present and the sheet opens; the full
//     pick-and-send flow is covered by the desktop test (S17 gate).
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:extended_text_field/extended_text_field.dart';
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
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/message_reply/tencent_cloud_chat_message_input_reply_container.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness helpers (deliberately duplicated — test files must not share private
// helpers; see CLAUDE.md harness facts).
// ---------------------------------------------------------------------------

Widget _localized({required Widget child}) {
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

/// Recording SDK platform — same chokepoint as Tim2ToxSdkPlatform in
/// production (isCustomPlatform routing).
class _RecordingSdkPlatform extends TencentCloudChatSdkPlatform {
  _RecordingSdkPlatform({required this.history});

  final List<V2TimMessage> history;

  final List<({String? id, String receiver, String groupID, String? cloudCustomData})>
      sendCalls = [];
  final List<List<String>> deleteCalls = [];
  final List<String> forwardCreateCalls = [];

  final Map<String, V2TimMessage> _createdById = {};
  int _createSeq = 0;

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
        userID: 'friend1',
        showName: 'Friend One',
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
    final id = 'mob_created_${_createSeq++}';
    final msg = V2TimMessage(
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: text),
      isSelf: true,
    );
    _createdById[id] = msg;
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(id: id, messageInfo: msg),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimMsgCreateInfoResult>> createForwardMessage({
    String? msgID,
    String? webMessageInstance,
  }) async {
    forwardCreateCalls.add(msgID ?? '');
    final source = history.firstWhere((m) => m.msgID == msgID);
    final id = 'mob_fwd_${_createSeq++}';
    final msg = V2TimMessage(
      elemType: source.elemType,
      textElem: source.textElem == null
          ? null
          : V2TimTextElem(text: source.textElem!.text),
      customElem: source.customElem == null
          ? null
          : V2TimCustomElem(data: source.customElem!.data),
      isSelf: true,
    );
    _createdById[id] = msg;
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(id: id, messageInfo: msg),
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
    sendCalls.add((
      id: id,
      receiver: receiver,
      groupID: groupID,
      cloudCustomData: cloudCustomData,
    ));
    final created = (id == null ? null : _createdById[id]) ??
        V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT);
    final echoed = V2TimMessage(
      msgID: id,
      id: id,
      elemType: created.elemType,
      textElem: created.textElem,
      customElem: created.customElem,
      isSelf: true,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      sender: 'self_user',
      cloudCustomData: cloudCustomData,
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    return V2TimValueCallback(code: 0, desc: 'ok', data: echoed);
  }

  @override
  Future<V2TimCallback> deleteMessages({
    List<String>? msgIDs,
    List<dynamic>? webMessageInstanceList,
  }) async {
    deleteCalls.add(List<String>.of(msgIDs ?? const []));
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
      'mob_test_uikit_listener';

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

// Fixture message texts / ids (must not clash with the desktop test's globals
// since both files share the same process in a full-suite run).
const _mobReceivedText = 'mob-heads-up';
const _mobSelfOldText = 'mob-ack';
const _mobSelfFreshText = 'mob-fresh-ping';

List<V2TimMessage> _buildMobileFixtureHistory() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return [
    V2TimMessage(
      msgID: 'mob_fresh',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _mobSelfFreshText),
      isSelf: true,
      timestamp: now - 30,
      sender: 'self_user',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'mob_custom',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
      // Valid JSON custom elem.  json.decode succeeds; the customerServicePlugin
      // == 0 branch is not triggered; the message falls through to the standard
      // row layout and renders via TencentCloudChatMessageCustom.defaultBuilder
      // which calls handleCustomMessage() → Text('[Custom]').
      // Non-JSON custom data (the bug fixed in BUG-1) is tested separately in
      // custom_elem_mobile_render_regression_test.dart.
      customElem: V2TimCustomElem(data: '{"type":"mob_reply_probe"}'),
      isSelf: false,
      timestamp: now - 300,
      sender: 'friend1',
      nickName: 'Friend One',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'mob_1',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _mobSelfOldText),
      isSelf: true,
      timestamp: now - 3500,
      sender: 'self_user',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'mob_0',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _mobReceivedText),
      isSelf: false,
      timestamp: now - 3600,
      sender: 'friend1',
      nickName: 'Friend One',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  ];
}

/// Mounts the REAL chat page at a 400×800 mobile viewport with
/// DeviceScreenType.mobile so the fork's defaultBuilder (long-press menu) is
/// exercised.
Future<_RecordingSdkPlatform> _pumpMobileChatPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.mobile;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  data.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'self_user', nickName: 'Me'));
  data.conversation.conversationList = [
    V2TimConversation(
        conversationID: 'c2c_friend1',
        type: 1,
        userID: 'friend1',
        showName: 'Friend One'),
    V2TimConversation(
        conversationID: 'c2c_friend2',
        type: 1,
        userID: 'friend2',
        showName: 'Friend Two'),
  ];
  data.messageData.messageListMap = {};
  addTearDown(() {
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
    data.basic.usedComponents = [];
  });

  final platform = _RecordingSdkPlatform(history: _buildMobileFixtureHistory());
  final oldPlatform = TencentCloudChatSdkPlatform.instance;
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

  await tester.pumpWidget(
    _localized(
      child: TencentCloudChatMessage(
        options: TencentCloudChatMessageOptions(userID: 'friend1'),
        config: TencentCloudChatMessageConfig(),
        builders: TencentCloudChatMessageBuilders(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();

  // Verify the fixture loaded.
  expect(_mobRowItem('mob_0'), findsOneWidget,
      reason: 'fixture received bubble must render in the mobile real list');
  expect(_mobRowItem('mob_1'), findsOneWidget,
      reason: 'fixture self bubble must render in the mobile real list');
  return platform;
}

// FINDER NOTE: same FlutterSliverList offstage behaviour as desktop; row-level
// finders use skipOffstage: false. Overlay menu items / dialogs use onstage
// (default).

Finder _mobRowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

Finder _mobTextBubbleCore(String msgID) =>
    find.byKey(Key(msgID), skipOffstage: false).last;

/// The custom-elem bubble core — the [Custom] text leaf widget.  On mobile the
/// custom message renders as a Row containing Text('[Custom]').  Using the text
/// leaf gives a correctly-reported globalToLocal position (leaf render objects
/// are correctly positioned even inside FlutterSliverList).
Finder _mobCustomBubbleCore() => find.text('[Custom]', skipOffstage: false);

Finder _mobMenuItem(String action) =>
    find.byKey(ValueKey('message_menu_item:$action'));

Finder _allMobMenuItems() => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('message_menu_item:');
    });

/// Long-press trigger for the mobile menu.
///
/// FlutterListView / FlutterSliverList children report incorrect global
/// positions via localToGlobal (the sliver transform is not reflected in
/// RenderBox.localToGlobal for state widgets).  Leaf render objects (Text,
/// ExtendedText) do report correct positions.  Always pass a leaf-level
/// finder (text content, icon) rather than a container widget key.
Future<void> _longPress(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  // The mobile menu uses animation controllers (~200ms) before inserting the
  // overlay entry.  Run the animations to completion.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

/// Dismiss the mobile overlay by tapping the backdrop (first matching
/// GestureDetector with a transparent BackdropFilter child, which is the
/// full-screen backdrop the fork inserts).
Future<void> _dismissMobileMenu(WidgetTester tester) async {
  // Tap the top-left corner — the backdrop GestureDetector covers the screen
  // and the menu itself is below-center, so (5,5) is reliably outside the menu.
  await tester.tapAt(const Offset(5, 5));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  testWidgets(
    'S15 mobile: long-press on a received text bubble opens the real menu with Copy/Forward/Delete',
    (tester) async {
      final platform = await _pumpMobileChatPage(tester);

      expect(_allMobMenuItems(), findsNothing,
          reason: 'menu must be closed before long-press');

      await _longPress(tester, _mobTextBubbleCore('mob_0'));

      // The REAL items for a received text message (same filtering as desktop):
      expect(_mobMenuItem('copy'), findsOneWidget);
      expect(_mobMenuItem('forward'), findsOneWidget);
      expect(_mobMenuItem('delete'), findsOneWidget);
      // Truthful negatives — fork strips these for TEXT messages:
      expect(_mobMenuItem('reply'), findsNothing,
          reason: 'fork removes reply from text-message menus on mobile too');
      expect(_mobMenuItem('multiSelect'), findsNothing);
      expect(_mobMenuItem('recall'), findsNothing,
          reason: 'received message: no recall');
      expect(_allMobMenuItems(), findsNWidgets(3),
          reason: 'text-message mobile menu must offer exactly copy/forward/delete');

      await _dismissMobileMenu(tester);
      expect(_allMobMenuItems(), findsNothing);
      expect(platform.sendCalls, isEmpty);
      expect(platform.deleteCalls, isEmpty);
    },
  );

  testWidgets(
    'S15 mobile: Recall appears only on a fresh self message (recall-window gating)',
    (tester) async {
      await _pumpMobileChatPage(tester);

      // Fresh self message — inside the recall window.
      await _longPress(tester, _mobTextBubbleCore('mob_fresh'));
      expect(_mobMenuItem('recall'), findsOneWidget,
          reason: 'fresh self message must offer Recall on mobile');
      expect(_mobMenuItem('copy'), findsOneWidget);
      expect(_mobMenuItem('forward'), findsOneWidget);
      expect(_mobMenuItem('delete'), findsOneWidget);
      await _dismissMobileMenu(tester);

      // Old self message — outside the recall window.
      await _longPress(tester, _mobTextBubbleCore('mob_1'));
      expect(_mobMenuItem('recall'), findsNothing,
          reason: 'recall must be absent once the window has passed (mobile)');
      expect(_mobMenuItem('copy'), findsOneWidget);
      await _dismissMobileMenu(tester);
    },
  );

  testWidgets(
    'S16 mobile: tapping the real Copy item puts the exact message text on the clipboard',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboardText;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final platform = await _pumpMobileChatPage(tester);

      await _longPress(tester, _mobTextBubbleCore('mob_0'));
      expect(clipboardText, isNull,
          reason: 'opening the mobile menu must not copy');

      await tester.tap(_mobMenuItem('copy'));
      await tester.pumpAndSettle();

      expect(clipboardText, _mobReceivedText,
          reason: 'Copy must place the verbatim bubble text on the clipboard (mobile)');
      // Copy is clipboard-only: no service traffic.
      expect(platform.sendCalls, isEmpty);
      expect(platform.deleteCalls, isEmpty);
    },
  );

  testWidgets(
    'S17 mobile: Forward opens bottom-sheet without overflow; pick target + Send forwards to that conversation',
    (tester) async {
      final platform = await _pumpMobileChatPage(tester);

      await _longPress(tester, _mobTextBubbleCore('mob_0'));
      // Forward IS in the real mobile menu — the same filtering path as desktop.
      expect(_mobMenuItem('forward'), findsOneWidget,
          reason: 'Forward must be offered in the mobile long-press menu');

      await tester.tap(_mobMenuItem('forward'));
      await tester.pumpAndSettle();

      // The overflow fix (Expanded around the TabBar in _renderTabBar) must
      // produce a clean render — no RenderFlex overflow exception.
      expect(tester.takeException(), isNull,
          reason: 'forward bottom-sheet must open without layout overflow at 400px');

      // The REAL mobile forward picker sheet: header + Recent tab.
      expect(find.text('Forward Individually'), findsOneWidget,
          reason: 'forward picker header must mount in the bottom sheet');
      expect(find.text('Friend Two'), findsOneWidget,
          reason: 'Recent tab must list the forward target');

      // Select the target conversation row.
      await tester.tap(find.text('Friend Two'));
      await tester.pumpAndSettle();
      expect(find.text('1 Chat'), findsOneWidget,
          reason: 'selection chip must reflect one selected chat (mobile)');

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      // sendForwardIndividuallyMessage defers the actual send by 100ms.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(platform.forwardCreateCalls, ['mob_0'],
          reason: 'forward must clone the source message on mobile');
      expect(platform.sendCalls, hasLength(1));
      expect(platform.sendCalls.single.receiver, 'friend2',
          reason: 'mobile forward send must target the picked conversation');
      // Picker sheet dismissed after Send.
      expect(find.text('Forward Individually'), findsNothing);
      // Source conversation unchanged.
      expect(_mobRowItem('mob_0'), findsOneWidget);
    },
  );

  testWidgets(
    'S18 mobile: Reply item on a quotable bubble drives the quote banner; send carries messageReply cloudCustomData',
    (tester) async {
      final platform = await _pumpMobileChatPage(tester);

      final customBubble = _mobCustomBubbleCore();
      expect(customBubble, findsOneWidget,
          reason: 'custom-elem bubble core must render in the mobile list');

      await _longPress(tester, customBubble);
      expect(_mobMenuItem('reply'), findsOneWidget,
          reason: 'Reply must be offered for quotable custom-elem bubble (mobile)');

      await tester.tap(_mobMenuItem('reply'));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      // The REAL quote banner mounts above the mobile composer.
      expect(find.byType(TencentCloudChatMessageInputReplyContainer),
          findsOneWidget,
          reason: 'tapping Reply on mobile must mount the composer quote banner');
      expect(find.text('Friend One'), findsWidgets,
          reason: 'quote banner shows the quoted sender');

      // Type into the mobile composer's ExtendedTextField and tap Send.
      final field = find.byType(ExtendedTextField);
      expect(field, findsWidgets);
      await tester.tap(field.first);
      await tester.pump();
      tester.testTextInput.enterText('mob-re: ack');
      await tester.pump();
      expect(platform.sendCalls, isEmpty,
          reason: 'typing alone must not send on mobile');

      // The mobile send button shows as Icons.arrow_upward_rounded once text
      // is present.
      final sendBtn = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendBtn, findsOneWidget,
          reason: 'mobile send button must appear once text is entered');
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(platform.sendCalls, hasLength(1));
      final call = platform.sendCalls.single;
      expect(call.receiver, 'friend1');
      expect(call.cloudCustomData, isNotNull,
          reason: 'mobile reply send must carry cloudCustomData');
      final decoded =
          jsonDecode(call.cloudCustomData!) as Map<String, dynamic>;
      expect(decoded, contains('messageReply'));
      final reply = decoded['messageReply'] as Map<String, dynamic>;
      expect(reply['messageID'], 'mob_custom');
      expect(reply['messageSender'], 'Friend One');

      expect(find.byType(TencentCloudChatMessageInputReplyContainer),
          findsNothing,
          reason: 'send must clear the quote banner on mobile');
      expect(_mobRowItem(call.id!), findsOneWidget,
          reason: 'sent reply must appear in the real mobile message list');
    },
  );

  testWidgets(
    'S15 mobile delete leg: Delete -> confirm dialog -> message not hit-testable; deleteMessages fires',
    (tester) async {
      final platform = await _pumpMobileChatPage(tester);

      await _longPress(tester, _mobTextBubbleCore('mob_1'));
      await tester.tap(_mobMenuItem('delete'));
      await tester.pumpAndSettle();

      // Mobile delete shows a confirmation dialog (same real path as desktop).
      const confirmKey = ValueKey('confirm_dialog_primary_button');
      expect(find.byKey(confirmKey), findsOneWidget,
          reason: 'mobile delete must ask for confirmation first');
      expect(platform.deleteCalls, isEmpty,
          reason: 'no deletion before confirm (mobile)');

      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(platform.deleteCalls, [
        ['mob_1']
      ], reason: 'confirm must invoke the real deletion handler (mobile)');

      // FlutterListView keeps mounted row widgets for previously-visible items
      // even after the backing list shrinks (same as desktop behaviour).
      // Assert data-layer drop (via deleteCalls above) then check hit-testable
      // absence — the widget is offstage after removal from the data model.
      expect(_mobRowItem('mob_1').hitTestable(), findsNothing,
          reason: 'deleted message must no longer be hit-testable on mobile');
      expect(_mobRowItem('mob_0'), findsOneWidget,
          reason: 'remaining messages must be unaffected');
    },
  );
}
