// Pins the two L3 result contracts the real-UI drivers gate on
// (lib/ui/testing/l3_composer_invite_tools.dart):
//
//   1. `l3_invite_to_group` — `ok` must follow the PER-MEMBER results, not the
//      SDK call code: the C++ `InviteUserToGroup` reports a refused
//      `tox_group_invite_friend` as `V2TIM_GROUP_MEMBER_RESULT_FAIL` under an
//      OnSuccess (code 0), which the old `code == 0` check read as "invite
//      sent" and the driver then waited 45 s for an auto-join that never came.
//   2. `l3_composer_send` — `seam` / `boundUserID` / `boundGroupID` must
//      describe the composer that IS mounted, straight from the fork's
//      `debugRealUi*ComposerBinding` seams, and must survive a keyed remount
//      (the successor composer registers BEFORE the predecessor disposes, so an
//      unconditional null in dispose wiped the live seams).
//
// The composer half mounts the REAL fork widgets (desktop + mobile) and reads
// the snapshot the tool returns; nothing here re-implements production logic.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

V2TimValueCallback<List<V2TimGroupMemberOperationResult>> _inviteResult(
  int code, {
  required List<V2TimGroupMemberOperationResult>? data,
}) {
  return V2TimValueCallback<List<V2TimGroupMemberOperationResult>>(
    code: code,
    desc: code == 0 ? 'success' : 'failed',
    data: data,
  );
}

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

MessageInputBuilderData _data({String? userID, String? groupID}) {
  return MessageInputBuilderData(
    userID: userID,
    groupID: groupID,
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    desktopMentionBoxPositionX: 0,
    desktopMentionBoxPositionY: 0,
    isGroupAdmin: false,
    activeMentionIndex: -1,
    currentFilteredMembersListForMention: const [],
    groupMemberList: const [],
    currentConversationShowName: groupID ?? userID ?? '',
    hasStickerPlugin: false,
    stickerPluginInstance: null,
  );
}

MessageInputBuilderMethods _methods() {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {},
    sendImageMessage:
        ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage:
        ({String? filePath, String? fileName, dynamic inputElement}) {},
    sendVoiceMessage: ({required String voicePath, required int duration}) {},
    onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
    controller: Object(),
    clearRepliedMessage: () {},
    setDesktopMentionBoxPositionX: (_) {},
    setDesktopMentionBoxPositionY: (_) {},
    setActiveMentionIndex: (_) {},
    setCurrentFilteredMembersListForMention: (_) {},
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder: Object(),
    closeSticker: () {},
  );
}

/// Mount ONE composer of [platform] bound to [userID]/[groupID] under [key].
/// A different key on the next pump is a keyed remount — exactly what a
/// conversation switch does to the composer.
Future<void> _pumpComposer(
  WidgetTester tester, {
  required String platform,
  required Key key,
  String? userID,
  String? groupID,
}) async {
  final data = _data(userID: userID, groupID: groupID);
  final composer = platform == 'desktop'
      ? TencentCloudChatMessageInputDesktop(
          key: key,
          inputData: data,
          inputMethods: _methods(),
          debugDraftPersistenceOnly: true,
        )
      : TencentCloudChatMessageInputMobile(
          key: key,
          inputData: data,
          inputMethods: _methods(),
          debugDraftPersistenceOnly: true,
        );
  await tester.pumpWidget(_localized(child: composer));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  group('l3_invite_to_group result contract', () {
    final succ = V2TimGroupMemberOperationResult(memberID: 'B', result: 1);
    final fail = V2TimGroupMemberOperationResult(memberID: 'B', result: 0);

    test('a per-member SUCC under code 0 is ok', () {
      final c = debugL3InviteResultContract(
        _inviteResult(0, data: [succ]),
        groupId: 'tox_3',
        userId: 'B',
      );
      expect(c['ok'], isTrue);
      expect(c.containsKey('error'), isFalse);
      expect(c['members'], [
        {'userId': 'B', 'result': 1},
      ]);
      expect(c['groupId'], 'tox_3');
      expect(c['userId'], 'B');
    });

    test('a per-member FAIL under code 0 is NOT ok (the lost-invite case)', () {
      final c = debugL3InviteResultContract(
        _inviteResult(0, data: [fail]),
        groupId: 'tox_3',
        userId: 'B',
      );
      expect(c['ok'], isFalse);
      expect(c['error'], 'member_invite_failed');
      expect(c['code'], 0);
      expect(c['members'], [
        {'userId': 'B', 'result': 0},
      ]);
    });

    test('one FAIL among several members is NOT ok', () {
      final c = debugL3InviteResultContract(
        _inviteResult(
          0,
          data: [
            succ,
            V2TimGroupMemberOperationResult(memberID: 'C', result: 0),
          ],
        ),
        groupId: 'tox_3',
        userId: 'B',
      );
      expect(c['ok'], isFalse);
      expect(c['error'], 'member_invite_failed');
    });

    test('a non-zero SDK code is NOT ok even with SUCC members', () {
      final c = debugL3InviteResultContract(
        _inviteResult(-1, data: [succ]),
        groupId: 'tox_3',
        userId: 'B',
      );
      expect(c['ok'], isFalse);
      expect(c['error'], 'invite_failed');
    });

    test('no member result at all is NOT ok', () {
      for (final data in <List<V2TimGroupMemberOperationResult>?>[null, []]) {
        final c = debugL3InviteResultContract(
          _inviteResult(0, data: data),
          groupId: 'tox_3',
          userId: 'B',
        );
        expect(c['ok'], isFalse, reason: 'data=$data');
        expect(c['error'], 'no_member_result');
        expect(c['members'], isEmpty);
      }
    });
  });

  group('l3_composer_send seam snapshot', () {
    testWidgets('nothing mounted reports seam none', (tester) async {
      await tester.pumpWidget(const SizedBox());
      expect(debugL3ComposerSeamSnapshot(), {
        'seam': 'none',
        'boundUserID': null,
        'boundGroupID': null,
      });
    });

    for (final platform in const ['desktop', 'mobile']) {
      testWidgets('$platform composer reports its binding, survives a keyed '
          'remount, and clears on unmount', (tester) async {
        tester.view.physicalSize = platform == 'desktop'
            ? const Size(1400, 900)
            : const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpComposer(
          tester,
          platform: platform,
          key: const ValueKey('group-composer'),
          groupID: 'tox_1',
        );
        expect(debugL3ComposerSeamSnapshot(), {
          'seam': platform,
          'boundUserID': null,
          'boundGroupID': 'tox_1',
        });

        // Keyed remount to a C2C chat: the successor registers in initState
        // BEFORE the predecessor's dispose runs (deactivate → inflate →
        // finalizeTree), so the snapshot must now be the successor's — an
        // unconditional null in dispose left `seam: none` here.
        await _pumpComposer(
          tester,
          platform: platform,
          key: const ValueKey('c2c-composer'),
          userID: 'FRIEND',
        );
        expect(debugL3ComposerSeamSnapshot(), {
          'seam': platform,
          'boundUserID': 'FRIEND',
          'boundGroupID': null,
        });

        await tester.pumpWidget(const SizedBox());
        expect(debugL3ComposerSeamSnapshot(), {
          'seam': 'none',
          'boundUserID': null,
          'boundGroupID': null,
        });
      });
    }
  });
}
