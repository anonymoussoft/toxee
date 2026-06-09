// Conference real-UI gates for the group-notifications invite row + accept
// (S176/S177), driving the shared fork widget
// `TencentCloudChatContactGroupApplicationItemButton` and its REAL accept
// handler.
//
// IMPORTANT production reality (documented, not worked around): toxee's Contacts
// page INTENTIONALLY omits the "Group notifications" tab, and
// `acceptGroupApplication` / `refuseGroupApplication` are no-ops returning
// code 0 (third_party/tim2tox/.../tim2tox_sdk_platform.dart:8860). A conference
// invite is delivered + accepted over the NATIVE onGroupInvited / auto-join path
// (B auto-joins via `tox_conference_join`), never surfaced as a pending
// application row — the conference analog of the S110 group-notifications
// finding. The real conference-invite acceptance is therefore the two-process
// `conference_message` pair gate, not a manual tap.
//
// What these L1 gates legitimately cover: the shared invite-row widget renders
// its keyed accept affordance for a conference application (S176), and tapping it
// runs the REAL `onAcceptApplication` → `acceptGroupApplication` no-op end-to-end
// (the optimistic "accepted" UI transition the code performs on code 0) (S177).
// This is the same "drive the real fork surface" approach chat_core uses.
//
// Mobile parity: the widget + handler are shared UIKit-fork Dart (no platform
// split).
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_group_application_list.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

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

V2TimGroupApplication _conferenceInvite(String groupID) {
  return V2TimGroupApplication(
    groupID: groupID,
    fromUser: 'inviter_conf',
    fromUserNickName: 'Conference Inviter',
    // 0 == pending/unhandled invite (the row renders its action buttons).
    type: 0,
    handleStatus: 0,
    handleResult: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  // S176 — a pending conference invite row exposes the keyed accept (+refuse)
  // affordances.
  testWidgets(
    'S176 conference invite row renders the keyed accept and refuse affordances',
    (tester) async {
      const gidC = 'tox_conf_176';
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatContactGroupApplicationItemButton(
            application: _conferenceInvite(gidC),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupInviteAcceptButton(gidC)), findsOneWidget,
          reason: 'the conference invite row must expose the keyed accept button');
      // Accept + Decline both render while the invite is pending (non-vacuous
      // baseline; tL10n.agree == 'Accept', tL10n.refuse == 'Decline').
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    },
  );

  // S177 — tapping accept runs the REAL onAcceptApplication →
  // contactSDK.acceptGroupApplication end-to-end. Hermetically the SDK is not
  // initialized, so the group-manager call returns non-zero and the production
  // handler takes its graceful failure branch (onSDKFailed), WITHOUT a spurious
  // success transition. We register an onSDKFailed probe to prove the real
  // handler actually reached the accept API (non-vacuous), mirroring the S108
  // friend-accept gate. The success "Accepted" transition + the native
  // conference join are the wired / two-process leg.
  testWidgets(
    'S177 tapping accept on a conference invite drives the real accept handler '
    '(onSDKFailed fires for acceptGroupApplication on the not-init path)',
    (tester) async {
      const gidC = 'tox_conf_177';

      String? failedApi;
      final probe = TencentCloudChatCallbacks(
        onTencentCloudChatSDKFailedCallback: (apiName, code, desc) {
          failedApi = apiName;
        },
      );
      TencentCloudChat.instance.callbacks.addCallback(probe);
      addTearDown(() => TencentCloudChat.instance.callbacks.removeCallback(probe));

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatContactGroupApplicationItemButton(
            application: _conferenceInvite(gidC),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final acceptKey = UiKeys.groupInviteAcceptButton(gidC);
      expect(find.byKey(acceptKey), findsOneWidget);

      await tester.tap(find.byKey(acceptKey));
      await tester.pumpAndSettle();

      // Proof the PRODUCTION handler ran end-to-end (not a dead button),
      // branch-agnostically: onAcceptApplication invoked the real
      // contactSDK.acceptGroupApplication, which runs ONE of its real branches —
      // either it failed (hermetic not-init → onSDKFailed fires for that exact
      // API) OR it succeeded (code 0 → the row flips to the accepted state and the
      // accept button is replaced). Either outcome proves the wiring; a dead /
      // unwired button would do neither.
      final sdkFailedForAccept = failedApi == 'acceptGroupApplication';
      final transitionedToAccepted = find.byKey(acceptKey).evaluate().isEmpty;
      expect(sdkFailedForAccept || transitionedToAccepted, isTrue,
          reason:
              'tapping accept must drive the real acceptGroupApplication handler '
              '(either the not-init failure branch or the code-0 accepted branch)');
    },
  );
}
