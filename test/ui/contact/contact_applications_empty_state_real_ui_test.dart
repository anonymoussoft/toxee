// S109 — Contacts: friend-applications EMPTY state (real-UI, L1 WidgetTester gate)
//
// Proves BOTH rendering branches of the REAL
// TencentCloudChatContactApplicationList widget:
//
//   EMPTY branch  — applicationList: [] → the Center>Container keyed
//     'contact_applications_list_empty' renders with "No new application" text.
//     Asserts A1/A2/A4 from the S109 spec.
//
//   NON-EMPTY contrast — applicationList: [oneApplication] → the empty key is
//     ABSENT and an application-item row IS present (keyed
//     'contact_application_item:<userID>').  Makes the empty assertion
//     non-vacuous: if the empty branch were always-on, the contrast test would
//     fail because the empty key would still be found when a real item was
//     seeded.
//
// Coverage note: A3/A5 (l3_dump_state, badge count) are live-only L3 assertions
// that require a running instance — they are outside the scope of a hermetic
// WidgetTester gate and are covered by the L3 playbook.
//
// Mobile-parity: TencentCloudChatContactApplicationList is shared UIKit-fork
// code (not platform-specific); this gate covers iOS/Android at the same time.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// ---------------------------------------------------------------------------
// Harness helper
// ---------------------------------------------------------------------------

/// Wraps [child] in a MaterialApp that:
///   1. Registers all UIKit-fork localisation delegates so the fork's
///      `tL10n` singleton is resolved before any fork widget builds.
///      (TencentCloudChatState.didChangeDependencies calls
///       chatController.initGlobalAdapterInBuildPhase → TencentCloudChatIntl().init)
///   2. Sets locale to English so string assertions are stable.
Widget _harness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Reset singleton contact data between tests so they are order-independent.
  // -------------------------------------------------------------------------
  tearDown(() {
    // contactBuilder may have been installed for the non-empty contrast test.
    TencentCloudChat.instance.dataInstance.contact.contactBuilder = null;
  });

  // =========================================================================
  // EMPTY branch — S109 A1/A2/A4
  // =========================================================================
  testWidgets(
    'S109 EMPTY: applicationList:[] renders the keyed empty-state widget and '
    '"No new application" text; no application-item rows present',
    (tester) async {
      // Pump the REAL production widget with an empty list.
      // This drives the isNotEmpty == false branch at
      //   tencent_cloud_chat_contact_application_list.dart:34.
      await tester.pumpWidget(
        _harness(
          const TencentCloudChatContactApplicationList(applicationList: []),
        ),
      );
      // One pump resolves the Localizations futures; pumpAndSettle would spin
      // forever if any descendant has a perpetual animation, so a single pump
      // after the initial frame is sufficient for a static empty-state render.
      await tester.pump();

      // A1: the keyed empty-state Container is present.
      // Proves the real empty branch executed — not just 'some widget found'.
      final emptyFinder = find.byKey(UiKeys.contactApplicationsListEmpty);
      expect(
        emptyFinder,
        findsOneWidget,
        reason:
            'S109-A1: empty branch must render the keyed '
            "'contact_applications_list_empty' Container",
      );

      // A2: the Container's descendant contains the localised empty text.
      // Uses find.descendant so the assertion is scoped to the empty widget
      // and cannot match stray Text nodes elsewhere in the tree.
      expect(
        find.descendant(
          of: emptyFinder,
          matching: find.text('No new application'),
        ),
        findsOneWidget,
        reason:
            'S109-A2: the empty-state widget must contain the localised '
            '"No new application" text (tL10n.noNewApplication)',
      );

      // A4: no application-item rows rendered for an empty list.
      // Uses a Predicate finder rather than a fixed key so any
      // 'contact_application_item:*' ValueKey would be caught.
      final itemFinder = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>)
                .value
                .startsWith('contact_application_item:'),
      );
      expect(
        itemFinder,
        findsNothing,
        reason:
            'S109-A4: no application-item row keys may appear for an empty list',
      );
    },
  );

  // =========================================================================
  // NON-EMPTY contrast — makes the empty assertion above non-vacuous.
  // If the empty branch were always-on, this test would fail because the empty
  // key would still render even with a seeded application in the list.
  // =========================================================================
  testWidgets(
    'S109 NON-EMPTY contrast: applicationList with one entry renders the item '
    'row and NOT the empty-state key',
    (tester) async {
      // The non-empty branch (TencentCloudChatContactApplicationItem) calls
      // contact.contactBuilder?.getContact*Builder(…) for avatar/content/button.
      // Row.children rejects null entries; setting TencentCloudChatContactBuilders
      // makes the null-safe calls return real default sub-widgets.
      final contact = TencentCloudChat.instance.dataInstance.contact;
      contact.contactBuilder = TencentCloudChatContactBuilders();
      addTearDown(() => contact.contactBuilder = null);

      // Minimal real V2TimFriendApplication — only userID and type are required.
      // type == 1 (V2TIM_FRIEND_APPLICATION_COME_IN, an incoming request) lets
      // the button builder reach its non-result branch without a crash.
      final application = V2TimFriendApplication(
        userID: 'applicant_alice',
        nickname: 'Alice Applicant',
        type: 1,
      );

      await tester.pumpWidget(
        _harness(
          TencentCloudChatContactApplicationList(
            applicationList: [application],
          ),
        ),
      );
      await tester.pump();

      // The empty key must be ABSENT — proves the non-empty branch fired.
      expect(
        find.byKey(UiKeys.contactApplicationsListEmpty),
        findsNothing,
        reason:
            'NON-EMPTY contrast: empty-state key must be absent when an '
            'application is in the list',
      );

      // The application-item row IS present — keyed by the applicant's userID.
      // This is the real 'contact_application_item:<userID>' ValueKey from
      //   tencent_cloud_chat_contact_application_list.dart:227.
      expect(
        find.byKey(const ValueKey('contact_application_item:applicant_alice')),
        findsOneWidget,
        reason:
            'NON-EMPTY contrast: the real item row key must be present for '
            'the seeded application',
      );
    },
  );
}
