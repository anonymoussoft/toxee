// Conference real-UI gates for the toxee group-profile builder overrides
// (lib/ui/group/group_builder_override.dart). Conferences are modeled as
// `GroupType.AVChatRoom` with a `tox_conf_*` groupID (fake_provider.dart:515,
// fake_managers.dart:161). These tests drive the REAL production builders
// returned by `TencentCloudChatGroupProfileManager.builder` after
// `installOverrides()`, exactly as chat_core_real_ui_test.dart does for groups,
// but on the conference branch.
//
// Single-process scope: the group-profile ROUTE is not reachable from the
// two-process flutter_skill harness (the route is pushed, not a keyed shell
// widget), so the conference profile surfaces are asserted at the widget layer
// here. The native legs (the actual tox_conference rename propagation, the
// conversation-row removal after leave) are the documented two-process /
// data-path scenarios (S153/S123/S37 family).
//
// Mobile parity: the toxee group-profile overrides are shared Dart (no platform
// split) — these gates cover iOS/Android too.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:toxee/ui/group/group_builder_override.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

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

// Captures the rename platform write (groupSDK.setGroupInfo routes through the
// installed platform's setGroupInfo).
class _FakeGroupSdkPlatform extends TencentCloudChatSdkPlatform {
  V2TimGroupInfo? lastGroupInfo;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimCallback> setGroupInfo({required V2TimGroupInfo info}) async {
    lastGroupInfo = info;
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

// A conference V2TimGroupInfo: AVChatRoom type + tox_conf_* id.
V2TimGroupInfo _conference({
  String groupID = 'tox_conf_42',
  String groupName = 'Design Conference',
  int? role,
}) {
  return V2TimGroupInfo(
    groupID: groupID,
    groupName: groupName,
    groupType: GroupType.AVChatRoom,
    role: role,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match production: the SDK loads libtim2tox_ffi. Process-global; harmless for
  // these widget-only gates.
  setNativeLibraryName('tim2tox_ffi');

  // S166 — open profile from the chat header: the conference profile reuses the
  // SAME toxee override surfaces as a group. Assert the override builders render
  // their keyed surfaces (content/edit + id, chat button, member entry,
  // destructive rows) for a conference groupInfo.
  testWidgets(
    'S166 conference profile exposes the toxee override surfaces '
    '(content, chat button, member entry, destructive rows)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      // The member builder reads basic.currentUser.
      final oldCurrentUser =
          TencentCloudChat.instance.dataInstance.basic.currentUser;
      TencentCloudChat.instance.dataInstance.basic
          .updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: 'alice'));
      addTearDown(() {
        if (oldCurrentUser != null) {
          TencentCloudChat.instance.dataInstance.basic
              .updateCurrentUserInfo(userFullInfo: oldCurrentUser);
        }
      });

      final builders = TencentCloudChatGroupProfileManager.builder;
      final conf = _conference();

      await tester.pumpWidget(
        _localized(
          child: ListView(
            children: [
              builders.getGroupProfileContentBuilder(groupInfo: conf),
              builders.getGroupProfileChatButtonBuilder(groupInfo: conf),
              builders.getGroupProfileMemberBuilder(
                groupInfo: conf,
                groupMember: <V2TimGroupMemberFullInfo>[
                  V2TimGroupMemberFullInfo(userID: 'alice', nickName: 'Alice'),
                ],
                contactList: const <V2TimFriendInfo>[],
              ),
              builders.getGroupProfileDeleteButtonBuilder(
                groupInfo: conf,
                groupMemberList: const <V2TimGroupMemberFullInfo>[],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileEditNameButton), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileIdText), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileSendMessageButton), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileMembersEntry), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileClearHistoryButton), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileLeaveButton), findsOneWidget);
    },
  );

  // S167 — the profile Send Message tile routes back into the conference chat
  // via onNavigateToChat (a getter alias for the bound onTapContactItem).
  testWidgets(
    'S167 conference profile Send Message tile navigates back to the conference '
    'chat with the conference groupID',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final contact = TencentCloudChat.instance.dataInstance.contact;
      final oldHandlers = contact.contactEventHandlers;
      String? tappedGroupId;
      contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
        uiEventHandlers: TencentCloudChatContactUIEventHandlers(
          onTapContactItem: ({userID, groupID}) async {
            tappedGroupId = groupID;
            return true;
          },
        ),
      );
      addTearDown(() => contact.contactEventHandlers = oldHandlers);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileChatButtonBuilder(
            groupInfo: _conference(groupID: 'tox_conf_167'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tappedGroupId, isNull);
      expect(find.byKey(UiKeys.groupProfileSendMessageButton), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileSendMessageButton));
      await tester.pumpAndSettle();

      expect(tappedGroupId, 'tox_conf_167',
          reason:
              'the conference Send Message tile must route back to chat with '
              'the conference groupID');
    },
  );

  // S168 — edit the conference name: the keyed edit button opens the real rename
  // dialog (field + confirm/cancel).
  testWidgets(
    'S168 conference profile edit button opens the rename dialog',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileContentBuilder(
            groupInfo: _conference(groupID: 'tox_conf_168', groupName: 'Edit Me'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);
      expect(find.byKey(UiKeys.groupProfileEditNameButton), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileEditNameButton));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsOneWidget,
          reason: 'tapping edit must open the conference rename dialog');
      expect(find.byKey(UiKeys.groupProfileEditNameField), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  // S169 — the conference avatar surface renders the local-pick affordance
  // (tappable avatar + camera badge). The actual FilePicker open is a native
  // surface (not driven here); this asserts the override avatar surface that
  // toxee substitutes for the upstream preset-grid.
  testWidgets(
    'S169 conference profile avatar renders the local-pick surface '
    '(camera badge + tappable)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileAvatarBuilder(
            groupInfo: _conference(groupID: 'tox_conf_169'),
            groupMember: const <V2TimGroupMemberFullInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The local-pick camera badge signals the avatar is tappable (the toxee
      // override, not the upstream preset grid).
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget,
          reason: 'the conference avatar must show the local-pick camera badge');
      expect(find.byType(GestureDetector), findsWidgets,
          reason: 'the avatar must be wrapped in a tap target');
    },
  );

  // S170 — profile content shows the resolved conference ID surface.
  testWidgets(
    'S170 conference profile content shows the Group ID text surface',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileContentBuilder(
            groupInfo:
                _conference(groupID: 'tox_conf_1234', groupName: 'Conf 1234'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conf 1234'), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileIdText), findsOneWidget);
      expect(find.textContaining('Group ID:'), findsOneWidget);
      expect(find.textContaining('tox_conf_1234'), findsOneWidget,
          reason: 'the conference identifier must be shown in the profile content');
    },
  );

  // S178 — clear-history row opens the confirm dialog (conference branch).
  testWidgets(
    'S178 conference profile clear-history row opens the confirm dialog',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileDeleteButtonBuilder(
            groupInfo: _conference(
              groupID: 'tox_conf_178',
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
            ),
            groupMemberList: const <V2TimGroupMemberFullInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileClearHistoryButton), findsOneWidget);
      expect(find.text('Are you sure you want to clear the chat history?'),
          findsNothing);

      await tester.tap(find.byKey(UiKeys.groupProfileClearHistoryButton));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to clear the chat history?'),
          findsOneWidget,
          reason: 'clear-history must open the confirm dialog for a conference');
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  // S179 — leave/delete row for a conference OWNER opens the role-appropriate
  // confirm dialog. A conference (AVChatRoom, != Work) owner gets the
  // Disband/Dissolve branch (_checkIfQuitGroup: groupType != Work && OWNER →
  // quitGroup=false).
  testWidgets(
    'S179 conference OWNER leave row shows Disband and opens the disband confirm',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileDeleteButtonBuilder(
            groupInfo: _conference(
              groupID: 'tox_conf_179',
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            ),
            groupMemberList: const <V2TimGroupMemberFullInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileLeaveButton), findsOneWidget);
      expect(find.text('Disband Group'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);

      await tester.tap(find.byKey(UiKeys.groupProfileLeaveButton));
      await tester.pumpAndSettle();

      expect(find.text('Disband the group?'), findsOneWidget,
          reason: 'a conference owner must get the disband confirm dialog');
    },
  );

  // S180 — leaving the conference: a MEMBER gets the Leave branch
  // (quitGroup=true). Assert the role-appropriate Leave confirm opens and is
  // cancelable; the actual conversation-row removal is the native quit leg
  // (covered two-process / S123 family).
  testWidgets(
    'S180 conference MEMBER leave row shows Leave and the confirm is cancelable',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileDeleteButtonBuilder(
            groupInfo: _conference(
              groupID: 'tox_conf_180',
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
            ),
            groupMemberList: const <V2TimGroupMemberFullInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileLeaveButton), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Disband Group'), findsNothing);

      await tester.tap(find.byKey(UiKeys.groupProfileLeaveButton));
      await tester.pumpAndSettle();

      expect(find.text('Leave the group?'), findsOneWidget,
          reason: 'a conference member must get the Leave confirm dialog');
      // The confirm dialog wires the real quit handler; cancel returns to the
      // profile without mutating state (the destructive leave is the 2-proc leg).
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the group?'), findsNothing,
          reason: 'cancel must dismiss the confirm without leaving');
    },
  );

  // S183 — rename through the profile dialog refreshes the displayed conference
  // title (old name gone, new shown) and writes through the real setGroupInfo
  // platform call. The conversation-list-row refresh is the two-process half.
  testWidgets(
    'S183 conference profile rename refreshes the displayed title and writes '
    'setGroupInfo',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final oldPlatform = TencentCloudChatSdkPlatform.instance;
      final fakePlatform = _FakeGroupSdkPlatform();
      TencentCloudChatSdkPlatform.instance = fakePlatform;
      addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileContentBuilder(
            groupInfo: _conference(
              groupID: 'tox_conf_183',
              groupName: 'Before Conf Rename',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Before Conf Rename'), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileEditNameButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(UiKeys.groupProfileEditNameField),
        'After Conf Rename',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
      await tester.pumpAndSettle();

      expect(find.text('After Conf Rename'), findsOneWidget);
      expect(find.text('Before Conf Rename'), findsNothing,
          reason: 'the displayed conference title must refresh to the new name');
      expect(fakePlatform.lastGroupInfo, isNotNull);
      expect(fakePlatform.lastGroupInfo!.groupID, 'tox_conf_183');
      expect(fakePlatform.lastGroupInfo!.groupName, 'After Conf Rename');
    },
  );
}
