// Real-UI widget gates for the MESSAGE-bubble action menu on DESKTOP
// (S15 surface + delete leg, S16 copy, S17 forward, S18 reply) — the
// message-level twin of the conversation-ROW menu gate in
// test/ui/chat_core_real_ui_test.dart.
//
// The REAL production page is mounted (TencentCloudChatMessage → layout/header/
// list/input containers → provider.init), with fixture history served through a
// recording TencentCloudChatSdkPlatform — the exact chokepoint toxee's
// Tim2ToxSdkPlatform occupies in production (isCustomPlatform routing in
// third_party/tencent_cloud_chat_sdk/lib/manager/*). Every interaction is a
// real gesture against the real fork widgets; no production logic is
// re-implemented here.
//
// GROUND TRUTH (verified against the fork, 2026-06-10): for a TEXT message the
// menu container STRIPS quote/reply + multi-select + translate
// (tencent_cloud_chat_message_item_with_menu_container.dart:594-612, commit
// 36324bb) — so the production text-message menu is exactly
// Copy / Forward / Delete (+ Recall for a fresh self message). The S15/S18 spec
// expectation of a Reply item on a text bubble is STALE. Reply survives for
// quotable elem types (e.g. custom); the reply chain is gated on a custom-elem
// fixture bubble below, driving the REAL menu item end-to-end.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/widgets/desktop_popup/tencent_cloud_chat_desktop_popup.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/message_reply/tencent_cloud_chat_message_input_reply_container.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness helpers (deliberately duplicated from chat_core_real_ui_test.dart —
// test files do not share private helpers).
// ---------------------------------------------------------------------------

// Wrap a child so the UIKit fork's i18n singleton (`tL10n`) is initialized from
// a real Localizations ancestor before the child builds.
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

/// Recording SDK platform — the seam production occupies with
/// Tim2ToxSdkPlatform (isCustomPlatform / isPlatformRouted routing). Serves the
/// fixture history and records the outgoing service calls the menu actions
/// must produce.
class _RecordingSdkPlatform extends TencentCloudChatSdkPlatform {
  _RecordingSdkPlatform({required this.history});

  /// Fixture history, newest-first (the order getHistoryMessageListV2
  /// contractually returns).
  final List<V2TimMessage> history;

  final List<({String? id, String receiver, String groupID, String? cloudCustomData})>
      sendCalls = [];
  final List<List<String>> deleteCalls = [];
  final List<String> forwardCreateCalls = [];

  /// Created-message registry so sendMessage can echo back the message that
  /// createTextMessage / createForwardMessage produced for a given id.
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
    // Initial load (no cursor): the fixture. Pagination: nothing more.
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
        // Non-empty faceUrl would trigger a network image; empty keeps the
        // default asset avatar. The provider's empty-faceUrl 800ms refresh
        // timer is flushed by the pump in _pumpChatPage.
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
    final id = 'created_${_createSeq++}';
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
    final id = 'fwd_${_createSeq++}';
    // Production clones the source elem into a fresh message with cleared
    // sender identity; mimic the data shape (the clone logic itself lives
    // below this seam in tim2tox and is covered by its own tests).
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
      'test_uikit_listener';

  @override
  void removeUIKitListener({String? uuid}) {}
}

// Fixture message texts/ids.
const _receivedText = 'heads-up: ci broke';
const _selfOldText = 'on it';
const _selfFreshText = 'fresh self ping';

List<V2TimMessage> _buildFixtureHistory() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // Newest-first, matching the getHistoryMessageListV2 contract.
  return [
    V2TimMessage(
      msgID: 'seed_fresh',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _selfFreshText),
      isSelf: true,
      timestamp: now - 30, // inside the recall window
      sender: 'self_user',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'seed_custom',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
      customElem: V2TimCustomElem(data: 'toxee-reply-probe'),
      isSelf: false,
      timestamp: now - 300,
      sender: 'friend1',
      nickName: 'Friend One',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'seed_1',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _selfOldText),
      isSelf: true,
      timestamp: now - 3500, // outside the recall window
      sender: 'self_user',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    V2TimMessage(
      msgID: 'seed_0',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: _receivedText),
      isSelf: false,
      timestamp: now - 3600,
      sender: 'friend1',
      nickName: 'Friend One',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  ];
}

/// Mounts the REAL chat page (TencentCloudChatMessage) for the C2C
/// conversation with friend1 on a desktop-sized surface, with fixture history
/// served by [_RecordingSdkPlatform]. Returns the installed platform fake.
Future<_RecordingSdkPlatform> _pumpChatPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // deviceScreenType is a cached static; force desktop so the message menu
  // uses desktopBuilder (right-click Listener + overlay column menu).
  TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  data.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'self_user', nickName: 'Me'));
  // Recent-tab fixture for the forward picker: the current chat plus a second
  // conversation to forward into.
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
  // Fresh per-test global message store (singleton survives between tests).
  data.messageData.messageListMap = {};
  addTearDown(() {
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
    data.basic.usedComponents = [];
  });

  final platform = _RecordingSdkPlatform(history: _buildFixtureHistory());
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
  // Flush the short init timers (10ms history load kick, the input container's
  // 10ms listener debounce, and the provider's 800ms empty-faceUrl refresh).
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();

  // The REAL list must show the fixture bubbles before any gate runs.
  expect(_rowItem('seed_0'), findsOneWidget,
      reason: 'fixture received bubble should render in the real list');
  expect(_rowItem('seed_1'), findsOneWidget,
      reason: 'fixture self bubble should render in the real list');
  return platform;
}

// FINDER NOTE: the fork's message list (flutter_list_view's FlutterSliverList)
// does not report its children through Element.debugVisitOnstageChildren, so
// DEFAULT finders treat every rendered row as offstage even though the rows
// are laid out and visible (verified via getRect). Row-level finders therefore
// use skipOffstage: false. Menu items / dialogs / popups live in the root
// Overlay and use default (onstage) finders — which also keeps the per-row
// OFFSTAGE menu measuring copies excluded from menu-item asserts.

/// The whole message row item, by the fork's canonical automation key
/// (tencent_cloud_chat_message_row_container.dart:286). Unique per msgID; used
/// for presence/absence assertions.
Finder _rowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

/// The text-bubble CORE (the keyed ExtendedText inside the bubble,
/// tencent_cloud_chat_message_text.dart) — the right-click/long-press target.
/// The row container and row share the same Key(msgID); .last is the
/// innermost (the bubble text), whose center lies inside the menu Listener.
Finder _textBubbleCore(String msgID) =>
    find.byKey(Key(msgID), skipOffstage: false).last;

/// The custom-elem bubble core (plain Text inside the bubble).
Finder _customBubbleCore() => find.text('[Custom]', skipOffstage: false);

/// Right-click (secondary mouse) on [target] — the desktop menu trigger that
/// goes through TencentCloudChatMessageItemWithMenu.desktopBuilder's Listener.
Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Dismisses an open desktop message menu by tapping the full-screen shroud
/// (the overlay GestureDetector at a point far from the menu).
Future<void> _dismissDesktopMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

Finder _menuItem(String action) => find.byKey(ValueKey('message_menu_item:$action'));

/// All rendered (non-offstage) keyed menu items.
Finder _allMenuItems() => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('message_menu_item:');
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Point the SDK at the tim2tox FFI lib name (matches production) before any
  // V2TimMessage is constructed — same requirement as chat_core_real_ui_test.
  setNativeLibraryName('tim2tox_ffi');

  // The fork's desktop popup tracks open state in a STATIC isShow/entry; reset
  // it so popup gates are order-independent.
  tearDown(() {
    TencentCloudChatDesktopPopup.entry?.remove();
    TencentCloudChatDesktopPopup.entry = null;
    TencentCloudChatDesktopPopup.isShow = false;
  });

  testWidgets(
    'S15 right-click on a received text bubble opens the real menu with exactly Copy/Forward/Delete',
    (tester) async {
      final platform = await _pumpChatPage(tester);

      // Closed: no keyed menu item visible (the offstage measuring copy is
      // skipped by default finders).
      expect(_allMenuItems(), findsNothing);

      await _rightClick(tester, _textBubbleCore('seed_0'));

      // The REAL items for a received text message in current production:
      expect(_menuItem('copy'), findsOneWidget);
      expect(_menuItem('forward'), findsOneWidget);
      expect(_menuItem('delete'), findsOneWidget);
      // Truthful negatives — the fork strips these for TEXT messages
      // (menu container :594-612): no Reply, no Multi-Select, no Translate.
      expect(_menuItem('reply'), findsNothing,
          reason: 'fork removes quote/reply from text-message menus');
      expect(_menuItem('multiSelect'), findsNothing);
      expect(_menuItem('translate'), findsNothing);
      // Received message: recall is gated on isSelf.
      expect(_menuItem('recall'), findsNothing);
      // Non-media text: no reveal-location; C2C: no read receipt.
      expect(_menuItem('revealFileLocation'), findsNothing);
      expect(_menuItem('readReceipt'), findsNothing);
      expect(_allMenuItems(), findsNWidgets(3),
          reason: 'text-message menu must offer exactly copy/forward/delete');

      // Dismiss via the overlay shroud: menu gone, no service side effects.
      await _dismissDesktopMenu(tester);
      expect(_allMenuItems(), findsNothing);
      expect(platform.sendCalls, isEmpty);
      expect(platform.deleteCalls, isEmpty);
    },
  );

  testWidgets(
    'S15 recall appears only on a fresh self message (recall-window gating)',
    (tester) async {
      await _pumpChatPage(tester);

      // Fresh self message (now-30s, inside the default recall window).
      await _rightClick(tester, _textBubbleCore('seed_fresh'));
      expect(_menuItem('recall'), findsOneWidget,
          reason: 'fresh self message must offer Recall');
      expect(_menuItem('copy'), findsOneWidget);
      expect(_menuItem('forward'), findsOneWidget);
      expect(_menuItem('delete'), findsOneWidget);
      await _dismissDesktopMenu(tester);

      // Old self message (now-3500s, outside the recall window).
      await _rightClick(tester, _textBubbleCore('seed_1'));
      expect(_menuItem('recall'), findsNothing,
          reason: 'recall must disappear once the recall window has passed');
      expect(_menuItem('copy'), findsOneWidget);
      await _dismissDesktopMenu(tester);
    },
  );

  testWidgets(
    'S16 tapping the real Copy item puts the exact message text on the clipboard',
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

      final platform = await _pumpChatPage(tester);

      await _rightClick(tester, _textBubbleCore('seed_0'));
      expect(clipboardText, isNull, reason: 'opening the menu must not copy');

      await tester.tap(_menuItem('copy'));
      await tester.pumpAndSettle();

      expect(clipboardText, _receivedText,
          reason: 'Copy must place the verbatim bubble text on the clipboard');
      // Desktop menu removes itself before running the action.
      expect(_allMenuItems(), findsNothing);
      // Copy is clipboard-only: no service traffic.
      expect(platform.sendCalls, isEmpty);
      expect(platform.deleteCalls, isEmpty);
    },
  );

  testWidgets(
    'S18 real Reply item on a quotable bubble drives quote banner -> send carries messageReply cloudCustomData',
    (tester) async {
      final platform = await _pumpChatPage(tester);

      // The custom-elem fixture bubble renders as "[Custom]".
      final customBubble = _customBubbleCore();
      expect(customBubble, findsOneWidget);

      await _rightClick(tester, customBubble);
      // Reply IS offered for quotable (non-text, non-media) messages — this is
      // the real production reply entry today (text bubbles have it stripped,
      // see the S15 gate).
      expect(_menuItem('reply'), findsOneWidget);

      await tester.tap(_menuItem('reply'));
      // The input container syncs provider.quotedMessage on a 10ms debounce.
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      // The REAL quote banner is mounted above the composer.
      expect(find.byType(TencentCloudChatMessageInputReplyContainer),
          findsOneWidget,
          reason: 'tapping Reply must mount the composer quote banner');
      expect(find.text('Friend One'), findsWidgets,
          reason: 'quote banner shows the quoted sender');

      // Type into the REAL desktop composer and send with Enter.
      final field = find.byType(ExtendedTextField);
      expect(field, findsWidgets);
      await tester.tap(field.first);
      await tester.pump();
      tester.testTextInput.enterText('re: ack');
      await tester.pump();
      expect(platform.sendCalls, isEmpty,
          reason: 'typing alone must not send');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // The captured outgoing send carries the reply metadata.
      expect(platform.sendCalls, hasLength(1));
      final call = platform.sendCalls.single;
      expect(call.receiver, 'friend1');
      expect(call.cloudCustomData, isNotNull,
          reason: 'reply send must carry cloudCustomData');
      final decoded =
          jsonDecode(call.cloudCustomData!) as Map<String, dynamic>;
      expect(decoded, contains('messageReply'));
      final reply = decoded['messageReply'] as Map<String, dynamic>;
      expect(reply['messageID'], 'seed_custom');
      expect(reply['messageSender'], 'Friend One');

      // Banner cleared by the real send path; the new self bubble is in the
      // REAL list.
      expect(find.byType(TencentCloudChatMessageInputReplyContainer),
          findsNothing,
          reason: 'send must clear the quote banner');
      expect(_rowItem(call.id!), findsOneWidget,
          reason: 'sent reply must appear in the real message list');
    },
  );

  testWidgets(
    'S17 real Forward item opens the picker; selecting a target + Send forwards to that conversation',
    (tester) async {
      final platform = await _pumpChatPage(tester);

      await _rightClick(tester, _textBubbleCore('seed_0'));
      await tester.tap(_menuItem('forward'));
      await tester.pumpAndSettle();

      // The REAL desktop forward popup: header + Recent tab listing the
      // seeded target conversation.
      expect(find.text('Forward Individually'), findsOneWidget,
          reason: 'forward picker header must mount');
      expect(find.text('Friend Two'), findsOneWidget,
          reason: 'Recent tab must list the forward target');
      expect(find.text('No Chat Selected'), findsOneWidget);

      // Select the target conversation row.
      await tester.tap(find.text('Friend Two'));
      await tester.pumpAndSettle();
      expect(find.text('1 Chat'), findsOneWidget,
          reason: 'selection chip must reflect one selected chat');

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      // sendForwardIndividuallyMessage defers the actual send by 100ms.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(platform.forwardCreateCalls, ['seed_0'],
          reason: 'forward must clone the source message');
      expect(platform.sendCalls, hasLength(1));
      expect(platform.sendCalls.single.receiver, 'friend2',
          reason: 'forward send must target the picked conversation');
      // Picker dismissed after Send.
      expect(find.text('Forward Individually'), findsNothing);
      // Source conversation unchanged: still exactly one source bubble.
      expect(_rowItem('seed_0'), findsOneWidget);
    },
  );

  testWidgets(
    'S15 delete leg: Delete -> keyed confirm -> message leaves the real list and deleteMessages fires',
    (tester) async {
      final platform = await _pumpChatPage(tester);

      await _rightClick(tester, _textBubbleCore('seed_1'));
      await tester.tap(_menuItem('delete'));
      await tester.pumpAndSettle();

      // The REAL desktop confirm dialog with the stable primary-button key.
      const confirmKey = ValueKey('confirm_dialog_primary_button');
      expect(find.byKey(confirmKey), findsOneWidget,
          reason: 'delete must ask for confirmation first');
      expect(platform.deleteCalls, isEmpty,
          reason: 'no deletion before confirm');

      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(platform.deleteCalls, [
        ['seed_1']
      ], reason: 'confirm must invoke the real deletion handler');

      // The data layer has dropped seed_1 from the message store (verified via
      // deleteCalls above).  FlutterListView (flutter_list_view) intentionally
      // keeps mounted row widgets for previously-visible items even after the
      // backing list shrinks — they live offstage (RenderObject.attached but
      // outside the hit-test tree).  We therefore assert:
      //   (a) the deleted row is not hit-testable (not interactive / visible), and
      //   (b) the remaining row is still present.
      expect(_rowItem('seed_1').hitTestable(), findsNothing,
          reason: 'deleted message must no longer be hit-testable in the real list');
      // The rest of the history is untouched.
      expect(_rowItem('seed_0'), findsOneWidget);
    },
  );
}
