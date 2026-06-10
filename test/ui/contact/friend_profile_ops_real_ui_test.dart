// Friend (C2C) profile operation real-UI gates — S111/S112/S113/S114/S115.
//
// These drive the REAL fork profile widgets (tencent_cloud_chat_contact
// tencent_cloud_chat_user_profile_body.dart) through real taps/text entry:
//
//  - S115: the per-tile `friend_profile_send_message_tile` key targets the
//    SEND tile specifically (the toxee wrapper key around the whole
//    [Send, Voice, Video] row centers on the middle Voice tile — the keying
//    defect demonstrated geometrically below) and fires the production
//    onNavigateToChat hook (alias of onTapContactItem) with the friend's id.
//  - S113: the real edit-remark pencil button opens the real AlertDialog,
//    typed text + confirm dispatch `contactSDK.setFriendInfo` (captured at the
//    TencentCloudChatSdkPlatform routing layer) and the displayed name updates.
//  - S114: the real Do-Not-Disturb Switch dispatches
//    `setC2CReceiveMessageOpt` with mute (V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE) /
//    unmute (V2TIM_RECEIVE_MESSAGE) and the switch state persists across the
//    round trip. Captured via the widget's canonical constructor seam, NOT
//    the platform layer: the vendored v2_tim_message_manager.dart routes
//    setC2CReceiveMessageOpt platform-side only under `kIsWeb`, so on desktop
//    and mobile it flows TIMMessageManager -> native bindings, which in a
//    plain widget test short-circuits at isInitSDK() with
//    ERR_SDK_NOT_INITIALIZED before anything observable.
//  - S111: the clear-history destructive row opens the real adaptive confirm
//    dialog; Cancel captures nothing, Confirm dispatches
//    `clearC2CHistoryMessage` and dismisses the dialog.
//  - S112: the delete-friend destructive row opens a real adaptive confirm
//    dialog (the friend's display name in the body, keyed Cancel/Confirm).
//    Confirm dispatches `deleteFromFriendList([friend], BOTH)`, removes the
//    friend from the in-memory contact list, and pops the profile route; the
//    cancel leg dismisses the dialog and dispatches nothing.
//
// Capture seam (S111/S112/S113): the vendored SDK managers route these calls
// through `TencentCloudChatSdkPlatform.instance` when `isPlatformRouted`
// (v2_tim_friendship_manager.dart / v2_tim_message_manager.dart), so a fake
// platform with `isCustomPlatform => true` observes the REAL production
// dispatch — the same pattern as conference_profile_real_ui_test.dart (S183).
// S114 alone is not platform-routed off web (see above) and uses the widget's
// setC2CReceiveMessageOpt constructor seam instead.
//
// Mobile parity: every surface here is shared fork Dart (no desktop/mobile
// split in tencent_cloud_chat_user_profile_body.dart), so these gates cover
// iOS/Android too. The one platform branch (_navigateToChat mobile pops /
// desktop sets currentConversation) sits BEHIND the onNavigateToChat hook,
// which toxee installs on all platforms.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

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

// Captures the friend-profile operation writes at the SDK platform routing
// layer (isPlatformRouted short-circuits the vendored managers into this
// instance, before any FFI/native code would be touched).
class _FakeFriendOpsSdkPlatform extends TencentCloudChatSdkPlatform {
  final List<({String userID, String? friendRemark})> setFriendInfoCalls = [];
  final List<String> clearHistoryCalls = [];
  final List<({List<String> userIDList, int deleteType})> deleteFriendCalls =
      [];

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimCallback> setFriendInfo({
    required String userID,
    String? friendRemark,
    Map<String, String>? friendCustomInfo,
  }) async {
    setFriendInfoCalls.add((userID: userID, friendRemark: friendRemark));
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> clearC2CHistoryMessage({required String userID}) async {
    clearHistoryCalls.add(userID);
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimValueCallback<List<V2TimFriendOperationResult>>>
      deleteFromFriendList({
    required List<String> userIDList,
    required int deleteType,
  }) async {
    deleteFriendCalls.add(
        (userIDList: List.of(userIDList), deleteType: deleteType));
    return V2TimValueCallback<List<V2TimFriendOperationResult>>(
      code: 0,
      desc: 'ok',
      data: userIDList
          .map((u) => V2TimFriendOperationResult(userID: u, resultCode: 0))
          .toList(),
    );
  }
}

_FakeFriendOpsSdkPlatform _installFakePlatform() {
  final old = TencentCloudChatSdkPlatform.instance;
  final fake = _FakeFriendOpsSdkPlatform();
  TencentCloudChatSdkPlatform.instance = fake;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = old);
  return fake;
}

// Seeds the friend into the in-memory contact list (the profile widgets gate
// the edit-remark button and the delete-friend row on contactList membership)
// and removes it again on teardown so the process-global singleton stays clean.
void _seedFriend(String userID, {String? nickName}) {
  TencentCloudChat.instance.dataInstance.contact.buildFriendList(
    [
      V2TimFriendInfo(
        userID: userID,
        userProfile: V2TimUserFullInfo(userID: userID, nickName: nickName),
      ),
    ],
    'friend_profile_ops_real_ui_test',
  );
  addTearDown(() => TencentCloudChat.instance.dataInstance.contact
      .deleteFromFriendList([userID], 'friend_profile_ops_real_ui_test'));
}

const _sendTileKey = ValueKey('friend_profile_send_message_tile');
const _voiceTileKey = ValueKey('friend_profile_voice_call_tile');
const _videoTileKey = ValueKey('friend_profile_video_call_tile');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match production: the SDK loads libtim2tox_ffi. Process-global; harmless
  // for these widget-only gates (the fake platform routes before any FFI).
  setNativeLibraryName('tim2tox_ffi');

  // S115 — the per-tile Send key targets the SEND tile specifically and fires
  // the production navigate-to-chat hook with the friend's conversation id.
  testWidgets(
    'S115 Send Message tile key targets the Send tile (not the row) and '
    'fires the production navigate-to-chat hook for the friend',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final contact = TencentCloudChat.instance.dataInstance.contact;
      final oldHandlers = contact.contactEventHandlers;
      var navCount = 0;
      String? navUserId;
      String? navGroupId;
      contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
        uiEventHandlers: TencentCloudChatContactUIEventHandlers(
          // onNavigateToChat (read by _navigateToChat) aliases onTapContactItem.
          onTapContactItem: ({userID, groupID}) async {
            navCount++;
            navUserId = userID;
            navGroupId = groupID;
            return true;
          },
        ),
      );
      addTearDown(() => contact.contactEventHandlers = oldHandlers);

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatUserProfileChatButton(
            userFullInfo:
                V2TimUserFullInfo(userID: 'friend-s115', nickName: 'Pat'),
            isNavigatedFromChat: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sendTile = find.byKey(_sendTileKey);
      expect(sendTile, findsOneWidget);
      // The key must sit on the SEND tile itself (message icon inside it),
      // and each action tile carries its own anchor.
      expect(
        find.descendant(
            of: sendTile, matching: find.byIcon(Icons.message_rounded)),
        findsOneWidget,
      );
      expect(find.byKey(_voiceTileKey), findsOneWidget);
      expect(find.byKey(_videoTileKey), findsOneWidget);

      // Keying-defect demonstration: the toxee wrapper key
      // (friendProfileSendMessageButton) wraps this WHOLE row widget, so a
      // wrapper-key tap lands at the row center — inside the middle VOICE
      // tile, NOT the Send tile. The per-tile key is the fix.
      final rowCenter =
          tester.getCenter(find.byType(TencentCloudChatUserProfileChatButton));
      expect(
        tester.getRect(sendTile).contains(rowCenter),
        isFalse,
        reason: 'the row center (where a whole-row wrapper-key tap lands) '
            'must NOT be inside the Send tile — that is the S115 defect',
      );
      expect(
        tester.getRect(find.byKey(_voiceTileKey)).contains(rowCenter),
        isTrue,
        reason: 'the row center lands on the middle Voice tile',
      );

      expect(navCount, 0);
      await tester.tap(sendTile);
      await tester.pumpAndSettle();

      expect(navCount, 1,
          reason: 'tapping the keyed Send tile must fire the production '
              'navigate-to-chat hook exactly once');
      expect(navUserId, 'friend-s115');
      expect(navGroupId, isNull,
          reason: 'a C2C profile must navigate to the friend conversation, '
              'not a group');
    },
  );

  // S113 — real edit-remark dialog: pencil button → type → confirm →
  // setFriendInfo dispatched AND the displayed name live-updates.
  testWidgets(
    'S113 edit-remark dialog saves through setFriendInfo and updates the '
    'displayed name',
    (tester) async {
      final fake = _installFakePlatform();
      _seedFriend('friend-s113', nickName: 'Bob');

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatUserProfileContent(
            userFullInfo:
                V2TimUserFullInfo(userID: 'friend-s113', nickName: 'Bob'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nameText = find.byKey(const ValueKey('user_profile_friend_name_text'));
      expect(nameText, findsOneWidget);
      expect(tester.widget<Text>(nameText).data, 'Bob',
          reason: 'with no remark the name falls back to the nickname');

      const dialogKey = ValueKey('user_profile_modify_remark_dialog');
      expect(find.byKey(dialogKey), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('user_profile_edit_remark_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget,
          reason: 'the pencil button must open the real modify-remark dialog');

      await tester.enterText(
        find.byKey(const ValueKey('user_profile_modify_remark_text_field')),
        'Bobby',
      );
      await tester.pumpAndSettle();
      await tester.tap(find
          .byKey(const ValueKey('user_profile_modify_remark_confirm_button')));
      await tester.pumpAndSettle();

      expect(fake.setFriendInfoCalls, hasLength(1));
      expect(fake.setFriendInfoCalls.single.userID, 'friend-s113');
      expect(fake.setFriendInfoCalls.single.friendRemark, 'Bobby');
      expect(find.byKey(dialogKey), findsNothing,
          reason: 'confirm must dismiss the dialog');
      expect(tester.widget<Text>(nameText).data, 'Bobby',
          reason: 'the displayed name must live-update to the saved remark');
    },
  );

  // S114 — real Do-Not-Disturb switch: each flip dispatches the production
  // receive-opt write (mute / unmute) and the switch state persists. Captured
  // at the SDK-call boundary via the widget's canonical constructor seam (the
  // vendored manager is not platform-routed off web — see file header).
  testWidgets(
    'S114 conversation mute switch flips setC2CReceiveMessageOpt and the '
    'switch state persists',
    (tester) async {
      final recvOptCalls =
          <({List<String> userIDList, ReceiveMsgOptEnum opt})>[];

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatUserProfileStateButton(
            userFullInfo: V2TimUserFullInfo(userID: 'friend-s114'),
            setC2CReceiveMessageOpt: ({
              required List<String> userIDList,
              required ReceiveMsgOptEnum opt,
            }) async {
              recvOptCalls.add((userIDList: List.of(userIDList), opt: opt));
              return V2TimCallback(code: 0, desc: 'ok');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final muteSwitch =
          find.byKey(const ValueKey('user_profile_conversation_mute_switch'));
      expect(muteSwitch, findsOneWidget);
      expect(tester.widget<Switch>(muteSwitch).value, isFalse,
          reason: 'no conversation cache entry → starts unmuted');

      await tester.tap(muteSwitch);
      await tester.pumpAndSettle();

      expect(recvOptCalls, hasLength(1));
      expect(recvOptCalls.single.userIDList, ['friend-s114']);
      expect(
        recvOptCalls.single.opt,
        ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE,
        reason: 'muting must write receive-but-do-not-notify',
      );
      expect(tester.widget<Switch>(muteSwitch).value, isTrue,
          reason: 'the switch must stay ON after a successful mute');

      await tester.tap(muteSwitch);
      await tester.pumpAndSettle();

      expect(recvOptCalls, hasLength(2));
      expect(
        recvOptCalls.last.opt,
        ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE,
        reason: 'unmuting must write normal receive',
      );
      expect(tester.widget<Switch>(muteSwitch).value, isFalse,
          reason: 'the switch must stay OFF after a successful unmute');
    },
  );

  // S111 — clear-chat-history row: real adaptive confirm dialog; Cancel is a
  // no-op, Confirm dispatches the production clearC2CHistoryMessage.
  testWidgets(
    'S111 clear-history row opens the confirm dialog; cancel is a no-op and '
    'confirm dispatches clearC2CHistoryMessage',
    (tester) async {
      final fake = _installFakePlatform();

      // NOT seeded as a friend: only the clear-history row renders, so this
      // gate cannot accidentally hit the delete-friend row (S112).
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatUserProfileDeleteButton(
            userFullInfo: V2TimUserFullInfo(userID: 'friend-s111'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clearRow =
          find.byKey(const ValueKey('user_profile_clear_history_button'));
      expect(clearRow, findsOneWidget);
      expect(
        find.byKey(const ValueKey('user_profile_delete_friend_button')),
        findsNothing,
        reason: 'a non-friend profile must not render the delete-friend row',
      );

      final confirmButton = find.byKey(
          const ValueKey('user_profile_clear_history_confirm_button'));
      expect(confirmButton, findsNothing);

      // Cancel leg: open the real confirm dialog, cancel → nothing dispatched.
      await tester.tap(clearRow);
      await tester.pumpAndSettle();
      expect(confirmButton, findsOneWidget,
          reason: 'the clear row must open the real confirm dialog');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmButton, findsNothing);
      expect(fake.clearHistoryCalls, isEmpty,
          reason: 'cancel must not clear anything');

      // Confirm leg: reopen, confirm → production clear handler dispatched.
      await tester.tap(clearRow);
      await tester.pumpAndSettle();
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(confirmButton, findsNothing,
          reason: 'confirm must dismiss the dialog');
      expect(fake.clearHistoryCalls, ['friend-s111'],
          reason: 'confirm must dispatch clearC2CHistoryMessage exactly once '
              'for the friend');
    },
  );

  // S112 — delete-friend row: deleting a friend is destructive, so the row now
  // opens a real confirm dialog FIRST. Confirm dispatches
  // deleteFromFriendList(BOTH), removes the friend from the in-memory contact
  // list, and pops the profile route; Cancel/barrier-dismiss dispatch nothing.
  // Keys are platform-agnostic: showAdaptiveDialog renders a CupertinoAlertDialog
  // on iOS/macOS and an AlertDialog elsewhere, but the dialog + both action
  // buttons carry stable ValueKeys, so we drive them by key, not by type.
  const openProfileKey = ValueKey('s112_open_profile_route');
  const dialogKey = ValueKey('user_profile_delete_friend_dialog');
  const confirmKey = ValueKey('user_profile_delete_friend_confirm_button');
  const cancelKey = ValueKey('user_profile_delete_friend_cancel_button');
  const deleteRowKey = ValueKey('user_profile_delete_friend_button');

  // Mounts the open-profile launcher at a 400px-wide (mobile) viewport so the
  // confirm dialog is exercised at phone width — no overflow is asserted by the
  // caller via tester.takeException().
  Future<void> pumpProfileLauncher(WidgetTester tester,
      {String? nickName = 'Del'}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
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
              return Center(
                child: TextButton(
                  key: openProfileKey,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: TencentCloudChatUserProfileDeleteButton(
                            userFullInfo: V2TimUserFullInfo(
                                userID: 'friend-s112', nickName: nickName),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open profile'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'S112 delete-friend row opens a confirm dialog; confirm dispatches '
    'deleteFromFriendList(BOTH), removes the friend and pops the profile route',
    (tester) async {
      final fake = _installFakePlatform();
      _seedFriend('friend-s112', nickName: 'Del');

      await pumpProfileLauncher(tester);
      await tester.tap(find.byKey(openProfileKey));
      await tester.pumpAndSettle();

      final deleteRow = find.byKey(deleteRowKey);
      expect(deleteRow, findsOneWidget,
          reason: 'a friend profile must render the delete-friend row');
      expect(
        TencentCloudChat.instance.dataInstance.contact.contactList
            .any((e) => e.userID == 'friend-s112'),
        isTrue,
      );

      // Tapping the row must NOT dispatch anything yet — it opens the dialog.
      await tester.tap(deleteRow);
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget,
          reason: 'the delete row must open the real confirm dialog');
      expect(find.byKey(confirmKey), findsOneWidget);
      expect(find.byKey(cancelKey), findsOneWidget);
      // Scoped to the dialog: the profile header also shows the nickname, so
      // a global find.text could false-pass without the body naming anyone.
      expect(
        find.descendant(
            of: find.byKey(dialogKey), matching: find.text('Del')),
        findsOneWidget,
        reason: 'the dialog body itself names the friend being removed',
      );
      expect(fake.deleteFriendCalls, isEmpty,
          reason: 'merely opening the confirm dialog must not delete anyone');
      expect(tester.takeException(), isNull,
          reason: 'the confirm dialog must lay out at 400px without overflow');

      // Confirm → production delete handler dispatched exactly once (BOTH).
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      expect(find.byKey(dialogKey), findsNothing,
          reason: 'confirm must dismiss the dialog');
      expect(fake.deleteFriendCalls, hasLength(1),
          reason: 'confirm must dispatch the production delete handler once');
      expect(fake.deleteFriendCalls.single.userIDList, ['friend-s112']);
      expect(
        fake.deleteFriendCalls.single.deleteType,
        FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH.index,
        reason: 'the profile delete must remove BOTH friendship directions',
      );
      expect(
        TencentCloudChat.instance.dataInstance.contact.contactList
            .any((e) => e.userID == 'friend-s112'),
        isFalse,
        reason: 'the production wrapper must drop the friend from the '
            'in-memory contact list on success',
      );
      expect(deleteRow, findsNothing,
          reason: 'the profile route must pop after a successful delete');
      expect(find.byKey(openProfileKey), findsOneWidget,
          reason: 'popping must land back on the previous route');
    },
  );

  // S112 (cancel leg) — Cancel closes the dialog and dispatches NOTHING; the
  // friend stays in the contact list and the profile route stays mounted.
  testWidgets(
    'S112 delete-friend confirm dialog: cancel is a no-op (nothing deleted, '
    'profile stays open)',
    (tester) async {
      final fake = _installFakePlatform();
      _seedFriend('friend-s112', nickName: 'Del');

      await pumpProfileLauncher(tester);
      await tester.tap(find.byKey(openProfileKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(deleteRowKey));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget);

      await tester.tap(find.byKey(cancelKey));
      await tester.pumpAndSettle();

      expect(find.byKey(dialogKey), findsNothing,
          reason: 'cancel must dismiss the dialog');
      expect(fake.deleteFriendCalls, isEmpty,
          reason: 'cancel must not delete anyone');
      expect(
        TencentCloudChat.instance.dataInstance.contact.contactList
            .any((e) => e.userID == 'friend-s112'),
        isTrue,
        reason: 'the friend must remain after cancel',
      );
      expect(find.byKey(deleteRowKey), findsOneWidget,
          reason: 'the profile route must stay open after cancel');
    },
  );

  // S112 (barrier leg) — tapping outside the dialog (barrierDismissible) is a
  // no-op exactly like Cancel: nothing deleted, profile stays mounted.
  testWidgets(
    'S112 delete-friend confirm dialog: barrier dismiss is a no-op',
    (tester) async {
      final fake = _installFakePlatform();
      _seedFriend('friend-s112', nickName: 'Del');

      await pumpProfileLauncher(tester);
      await tester.tap(find.byKey(openProfileKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(deleteRowKey));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget);

      // (8,8) is well outside the centered dialog at 400x800 → barrier tap.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byKey(dialogKey), findsNothing,
          reason: 'barrier tap must dismiss the dialog');
      expect(fake.deleteFriendCalls, isEmpty,
          reason: 'barrier dismiss must not delete anyone');
      expect(find.byKey(deleteRowKey), findsOneWidget,
          reason: 'the profile route must stay open after barrier dismiss');
    },
  );

  // S112 (double-fire leg) — the one-shot `handled` flag is the production
  // defense against a double-fired confirm (fast double-click, or a harness
  // dispatching synthetic pointer + direct callback): the second invoke must
  // neither dispatch a second delete nor pop the navigator a second time
  // (which would blank the app). Invoke onPressed twice in the same frame —
  // platform-agnostic across the Material/Cupertino action branches.
  testWidgets(
    'S112 delete-friend confirm double-fire dispatches exactly once and '
    'never double-pops',
    (tester) async {
      final fake = _installFakePlatform();
      _seedFriend('friend-s112', nickName: 'Del');

      await pumpProfileLauncher(tester);
      await tester.tap(find.byKey(openProfileKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(deleteRowKey));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget);

      final actionWidget = tester.widget(find.byKey(confirmKey));
      final VoidCallback onPressed = switch (actionWidget) {
        TextButton(:final onPressed?) => onPressed,
        CupertinoDialogAction(:final onPressed?) => onPressed,
        _ => throw StateError(
            'unexpected confirm action widget: ${actionWidget.runtimeType}'),
      };
      onPressed();
      onPressed(); // double-fire — must be a no-op
      await tester.pumpAndSettle();

      expect(fake.deleteFriendCalls, hasLength(1),
          reason: 'the one-shot flag must make the second invoke a no-op');
      expect(find.byKey(dialogKey), findsNothing);
      expect(find.byKey(openProfileKey), findsOneWidget,
          reason: 'the root route must survive (no double-pop blanking)');
    },
  );

  // S112 (empty-nickname leg) — the dialog body must fall back to the userID
  // when the nickname is empty, so the destructive dialog always names its
  // target (codex review regression, 2026-06-10).
  testWidgets(
    'S112 delete-friend confirm dialog names the userID when the nickname '
    'is empty',
    (tester) async {
      _installFakePlatform();
      _seedFriend('friend-s112', nickName: '');

      await pumpProfileLauncher(tester, nickName: '');
      await tester.tap(find.byKey(openProfileKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(deleteRowKey));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsOneWidget);

      expect(
        find.descendant(
            of: find.byKey(dialogKey), matching: find.text('friend-s112')),
        findsOneWidget,
        reason: 'an empty nickname must fall back to the userID in the body',
      );
    },
  );
}
