// Regular-NGC-group real-UI gates for the add-member picker chain
// (S144 / S145 / S124). The widgets under test are the SHARED UIKit-fork
// add-member picker (`tencent_cloud_chat_group_add_member.dart`):
//   * `TencentCloudChatGroupAddMember` — the picker page hosting the keyed
//     invite confirm (`group_member_invite_confirm_button`).
//   * `TencentCloudChatGroupProfileAddMemberList` — the AZ friend list whose
//     rows are keyed `add_member_contact_item:<friend.userID>`.
//
// These are the SAME widgets the conference twin
// (test/ui/conference/conference_members_real_ui_test.dart, S174/S175/S184)
// drives for an AVChatRoom; here we drive them for a REGULAR NGC group
// (`GroupType.Work`, `tox_group_*` id — toxee's private/work NGC convention),
// and — unlike the conference S184 which only proves the picker pops — we
// CAPTURE the production invite call and assert its parameters.
//
// Invite capture is at the canonical platform seam: the picker's real
// `submitAdd` runs `contactPresenter.inviteUserToGroup` →
// `getGroupManager().inviteUserToGroup` → (because the installed platform is a
// custom platform, `isPlatformRouted == true`) →
// `TencentCloudChatSdkPlatform.instance.inviteUserToGroup`
// (third_party/tencent_cloud_chat_sdk/lib/manager/v2_tim_group_manager.dart:380-388).
// We swap in a `_FakeGroupSdkPlatform` that records groupID + userList, exactly
// like conference_profile_real_ui_test.dart captures setGroupInfo. The
// production handler is driven end to end through real taps — no production
// logic is re-implemented in the test.
//
// Mobile parity: the add-member picker, the per-row keys and the confirm button
// are all shared UIKit-fork Dart (no platform split). This L1 coverage applies
// to iOS/Android too; the toxee group-profile override
// (lib/ui/group/group_builder_override.dart) does NOT override the add-member
// entry/picker, so this is upstream-shared on every platform.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_add_member.dart';
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

// A regular NGC group (private/work) the way toxee models it: GroupType.Work +
// a tox_group_* id. Distinct from the conference (AVChatRoom + tox_conf_*).
V2TimGroupInfo _workGroup({String groupID = 'tox_group_42'}) {
  return V2TimGroupInfo(
    groupID: groupID,
    groupName: 'Work Group',
    groupType: GroupType.Work,
    role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
  );
}

V2TimFriendInfo _friend(String userID, String nickName) {
  return V2TimFriendInfo(
    userID: userID,
    userProfile: V2TimUserFullInfo(userID: userID, nickName: nickName),
  );
}

// Captures the invite-to-group platform write. The picker's real submitAdd
// routes through the installed platform's inviteUserToGroup because a custom
// platform reports isPlatformRouted == true (v2_tim_group_manager.dart:384).
class _FakeGroupSdkPlatform extends TencentCloudChatSdkPlatform {
  String? lastGroupID;
  List<String>? lastUserList;
  int inviteCallCount = 0;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<List<V2TimGroupMemberOperationResult>>>
      inviteUserToGroup({
    required String groupID,
    required List<String> userList,
  }) async {
    inviteCallCount += 1;
    lastGroupID = groupID;
    lastUserList = List<String>.from(userList);
    return V2TimValueCallback<List<V2TimGroupMemberOperationResult>>(
      code: 0,
      desc: 'ok',
      data: [
        for (final id in userList)
          V2TimGroupMemberOperationResult(memberID: id, result: 1),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match production: the SDK loads libtim2tox_ffi. Process-global; harmless for
  // these widget-only gates (no native call is made — the platform seam below
  // intercepts the only SDK call this flow would issue).
  setNativeLibraryName('tim2tox_ffi');

  // S144 — add-member entry opens the REAL picker. A real tap on a host button
  // pushes the production `TencentCloudChatGroupAddMember` route for a Work
  // group; the picker mounts and renders its real selectable friend rows + the
  // keyed invite confirm. This is the picker-opens half of S124 for a regular
  // NGC group (the profile-body entry button itself routes through the UIKit
  // router singleton, an env-level concern the spec flags; the production
  // picker widget + a real route push are driven here).
  testWidgets(
    'S144 regular group add-member entry opens the real picker with the '
    'selectable friend rows and the keyed confirm',
    (tester) async {
      final friends = <V2TimFriendInfo>[
        _friend('amy_144', 'Amy'),
        _friend('ben_144', 'Ben'),
      ];

      await tester.pumpWidget(
        _localized(
          child: Builder(
            builder: (base) => Center(
              child: ElevatedButton(
                key: const ValueKey('open_group_picker'),
                onPressed: () => Navigator.of(base).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TencentCloudChatGroupAddMember(
                      groupInfo: _workGroup(groupID: 'tox_group_144'),
                      memberList: const <V2TimGroupMemberFullInfo>[],
                      contactList: friends,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The picker is not mounted until the real entry tap pushes it.
      expect(find.byKey(const ValueKey('group_member_invite_confirm_button')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('open_group_picker')));
      await tester.pumpAndSettle();

      // Real selectable friend rows rendered by the production AZ picker list.
      expect(
        find.byKey(const ValueKey('add_member_contact_item:amy_144')),
        findsOneWidget,
        reason: 'the picker must render the selectable friend rows',
      );
      expect(
        find.byKey(const ValueKey('add_member_contact_item:ben_144')),
        findsOneWidget,
      );
      // The keyed invite confirm affordance is present.
      expect(
        find.byKey(const ValueKey('group_member_invite_confirm_button')),
        findsOneWidget,
        reason: 'the picker must render the keyed invite confirm affordance',
      );
    },
  );

  // S145 — select a friend → confirm → the REAL production invite call fires.
  // Drive the picker end to end: tap a friend row (the real toggle selection),
  // tap confirm (the real submitAdd → inviteUserToGroup), and assert the
  // production invite was dispatched through the platform seam.
  testWidgets(
    'S145 regular group picker confirm dispatches the real inviteUserToGroup '
    'for the selected friend',
    (tester) async {
      final fakePlatform = _FakeGroupSdkPlatform();
      final oldPlatform = TencentCloudChatSdkPlatform.instance;
      TencentCloudChatSdkPlatform.instance = fakePlatform;
      addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

      final friends = <V2TimFriendInfo>[
        _friend('cara_145', 'Cara'),
      ];

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupAddMember(
            groupInfo: _workGroup(groupID: 'tox_group_145'),
            memberList: const <V2TimGroupMemberFullInfo>[],
            contactList: friends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing dispatched yet.
      expect(fakePlatform.inviteCallCount, 0);

      // Select the friend row (real toggle → onSelectedMemberItemChange).
      await tester.tap(
          find.byKey(const ValueKey('add_member_contact_item:cara_145')));
      await tester.pumpAndSettle();

      // Confirm — runs the real submitAdd (await-ing inviteUserToGroup) then
      // pops. runAsync so the awaited platform call completes deterministically.
      await tester.runAsync(() async {
        await tester
            .tap(find.byKey(const ValueKey('group_member_invite_confirm_button')));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      expect(fakePlatform.inviteCallCount, 1,
          reason:
              'confirming must dispatch the real inviteUserToGroup exactly once');
      expect(fakePlatform.lastUserList, isNotNull,
          reason: 'the invite must carry the selected friend list');
      expect(fakePlatform.lastUserList, contains('cara_145'),
          reason: 'the dispatched invite must target the selected friend');
    },
  );

  // S124 — assert the confirm PARAMETERS: the captured invite carries the exact
  // target group id and the exact selected member id(s). This is the
  // parameter-fidelity half of the add-member walk (S81 frames the same invite
  // from the data path).
  testWidgets(
    'S124 regular group picker confirm carries the target group id and the '
    'selected member ids',
    (tester) async {
      final fakePlatform = _FakeGroupSdkPlatform();
      final oldPlatform = TencentCloudChatSdkPlatform.instance;
      TencentCloudChatSdkPlatform.instance = fakePlatform;
      addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

      const groupID = 'tox_group_124';
      final friends = <V2TimFriendInfo>[
        _friend('dora_124', 'Dora'),
        _friend('evan_124', 'Evan'),
      ];

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupAddMember(
            groupInfo: _workGroup(groupID: groupID),
            memberList: const <V2TimGroupMemberFullInfo>[],
            contactList: friends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select two friends through the real picker rows.
      await tester.tap(
          find.byKey(const ValueKey('add_member_contact_item:dora_124')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('add_member_contact_item:evan_124')));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester
            .tap(find.byKey(const ValueKey('group_member_invite_confirm_button')));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      // Parameter fidelity: exact target group id.
      expect(fakePlatform.lastGroupID, groupID,
          reason: 'the invite must target the group the picker was opened for');
      // Parameter fidelity: exactly the selected member ids (order-independent).
      expect(fakePlatform.lastUserList, isNotNull);
      expect(fakePlatform.lastUserList!.toSet(), {'dora_124', 'evan_124'},
          reason:
              'the invite must carry exactly the member ids selected in the '
              'picker');
    },
  );
}
