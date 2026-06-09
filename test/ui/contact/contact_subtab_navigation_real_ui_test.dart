// Real-UI L1 gate for S106 — Contacts sub-tab navigation.
//
// The pre-existing anchor test (`contact_application_anchors_test.dart`) only
// stacks three *hand-fed* `TencentCloudChatContactTab`s and proves their KEYS
// render. It never exercises the real navigation: tapping a tab and watching the
// right panel mount. This gate pumps the ACTUAL production Contacts component
// (`TencentCloudChatContact`) forced to the DESKTOP layout — where a tab tap
// swaps the right pane in place via `setState` (`_desktopModule` + `_title`,
// tencent_cloud_chat_contact.dart desktopBuilder ~189-221) — then taps each
// real tab and asserts its panel widget is mounted and the pane title updates.
// That is the real navigation path, not a `find.byKey(...) findsOneWidget`.
//
// IMPORTANT toxee-specific reality (diverges from the upstream S106 spec):
// toxee's `TencentCloudChatContact.desktopBuilder` builds ONLY two sub-tabs —
// `new_contacts` and `blocked_users`. The upstream "Group notifications" tab
// (id `group_notification`, key `contact_group_notifications_tab`) was
// deliberately removed (tencent_cloud_chat_contact.dart:197-203): the Tox
// bridge has no group-application concept, so that entry only ever opened a
// permanently-empty, non-functional list. This gate therefore proves the two
// tabs toxee actually ships AND asserts the removed Group-Notifications key is
// absent on the real component — strictly more honest than the synthetic
// anchor test, whose A1 "all three keys" only holds because it manually
// fabricates a `group_notification` tab item that production never builds.
//
// Hermetic: no native lib, no network. Resets all UIKit singleton state in
// tearDown.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_block_list.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_group_application_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// Wrap the component so the UIKit fork's i18n singleton (`tL10n`) is initialized
// from a real Localizations ancestor before the widget builds. The Contacts
// desktopBuilder reads `tL10n.newContacts` / `tL10n.blockList` while building
// the tab list and throws if `tL10n` is uninitialized (REAL_UI_GATES.md recipe).
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

// Pumps the REAL toxee Contacts component forced to the desktop layout, with the
// minimum dataInstance wiring the fork needs to render the contact list + tabs:
//   * deviceScreenType = desktop so `TencentCloudChatState.build` dispatches to
//     `desktopBuilder` (the pane-swap arm) on any CI host — mirrors
//     chat_core_real_ui_test.dart.
//   * usedComponents must include `contact`, or the component's initState skips
//     seeding its lists from dataInstance.
//   * contactBuilder must be non-null: the tab is rendered through
//     `getContactListTabItemBuilder` (-> TencentCloudChatContactTabItem ->
//     TencentCloudChatContactTab, which carries the keyed wrappers) and the
//     AZ-list also renders rows through the builder; a null builder makes the
//     fork build throw.
// Resets every mutated singleton in tearDown so gates stay order-independent.
Future<void> _pumpContacts(WidgetTester tester) async {
  // Desktop viewport so the desktop pane-swap layout is selected.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // `deviceScreenType` is a cached static; a prior mobile-screen test could
  // leave it as mobile, which would route to the mobile (route-push) arm where
  // tabs Navigator.push instead of swapping the pane. Force desktop for this
  // gate and reset afterwards.
  TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.contact];
  // The fork builds tab/contact rows via the contact builder; null => throws.
  data.contact.contactBuilder = TencentCloudChatContactBuilders();
  addTearDown(() {
    data.contact.contactBuilder = null;
    data.basic.usedComponents = [];
  });

  await tester.pumpWidget(_localized(child: const TencentCloudChatContact()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop Contacts: both real sub-tabs render; the removed Group-Notifications tab is absent (A1)',
    (tester) async {
      await _pumpContacts(tester);

      // A1 (toxee form): the two sub-tabs toxee actually ships are present in
      // the live component (NOT a hand-stacked harness). These keys are emitted
      // by the real fork `TencentCloudChatContactTab` only when the parent feeds
      // it a tab item with the matching id, which toxee's desktopBuilder does.
      expect(
        find.byKey(UiKeys.contactNewContactsTab),
        findsOneWidget,
        reason: 'New Contacts sub-tab should render in the real Contacts pane',
      );
      expect(
        find.byKey(UiKeys.contactBlockedUsersTab),
        findsOneWidget,
        reason: 'Blocked Users sub-tab should render in the real Contacts pane',
      );

      // A1 honesty check: toxee deliberately removed the upstream "Group
      // notifications" tab, so its key must NOT appear on the production
      // component. (The anchor test's "all three keys" only holds because it
      // fabricates a group_notification tab item; this proves production does
      // not.) See tencent_cloud_chat_contact.dart:197-203.
      expect(
        find.byKey(UiKeys.contactGroupNotificationsTab),
        findsNothing,
        reason:
            'toxee removed the Group-Notifications sub-tab (no Tox group-application concept)',
      );
      // The corresponding panel type is therefore never mounted either.
      expect(
        find.byType(TencentCloudChatContactGroupApplicationList),
        findsNothing,
      );
    },
  );

  testWidgets(
    'desktop Contacts: tapping New Contacts swaps the pane to the application panel (A2)',
    (tester) async {
      await _pumpContacts(tester);

      // Before the tap the right pane is the empty placeholder, so the
      // New-Contacts panel is NOT mounted — its later appearance proves the tap
      // drove the real `setState` pane swap (non-vacuous).
      expect(find.byType(TencentCloudChatContactApplication), findsNothing);
      // Baseline count of "New Contacts" text BEFORE the tap (a static left-rail
      // tab label may already read it) so the title assertion below is non-vacuous.
      final newContactsBefore = find.text('New Contacts').evaluate().length;

      // REAL interaction: tap the keyed New Contacts tab (its onTap runs the
      // desktopBuilder closure that sets _desktopModule =
      // TencentCloudChatContactApplication + _title = tL10n.newContacts).
      await tester.tap(find.byKey(UiKeys.contactNewContactsTab));
      await tester.pumpAndSettle();

      // A2: the New-Contacts panel widget is now mounted in the right pane.
      expect(
        find.byType(TencentCloudChatContactApplication),
        findsOneWidget,
        reason: 'tapping New Contacts should mount the application panel',
      );
      // The pane TITLE updated too (rendered from `_title`): the tap ADDED at
      // least one more "New Contacts" text beyond the pre-tap baseline. The delta
      // (not a bare findsWidgets, which a static tab label alone would satisfy)
      // is what proves the title surfaced from the swap.
      expect(
        find.text('New Contacts').evaluate().length,
        greaterThan(newContactsBefore),
        reason: 'tapping New Contacts should surface the pane title from the swap',
      );
    },
  );

  testWidgets(
    'desktop Contacts: tapping Blocked Users swaps the pane to the block list (A4)',
    (tester) async {
      await _pumpContacts(tester);

      // Non-vacuous: the block-list panel is absent before the tap.
      expect(find.byType(TencentCloudChatContactBlockList), findsNothing);
      // Baseline count of "Blocked Users" text before the tap (left-rail tab
      // label) so the title delta below is non-vacuous.
      final blockedBefore = find.text('Blocked Users').evaluate().length;

      // REAL interaction: tap the keyed Blocked Users tab (onTap sets
      // _desktopModule = TencentCloudChatContactBlockList + _title =
      // tL10n.blockList).
      await tester.tap(find.byKey(UiKeys.contactBlockedUsersTab));
      await tester.pumpAndSettle();

      // A4: the Blocked-Users panel widget is mounted in the right pane.
      expect(
        find.byType(TencentCloudChatContactBlockList),
        findsOneWidget,
        reason: 'tapping Blocked Users should mount the block-list panel',
      );
      // The pane TITLE updated: the tap ADDED a "Blocked Users" text beyond the
      // pre-tap baseline (the delta, not a bare findsWidgets, is the proof).
      expect(
        find.text('Blocked Users').evaluate().length,
        greaterThan(blockedBefore),
        reason: 'tapping Blocked Users should surface the pane title from the swap',
      );
      // With an empty block list the panel also shows the localized empty-state
      // copy — proving the panel rendered its body, not just mounted.
      expect(
        find.text('No blocked users'),
        findsOneWidget,
        reason: 'empty block list should render the localized empty state',
      );
    },
  );

  testWidgets(
    'desktop Contacts: switching tabs back and forth re-swaps the live pane',
    (tester) async {
      // Proves the pane swap is the real, repeatable navigation state machine
      // (each tap replaces _desktopModule), not a one-shot mount.
      await _pumpContacts(tester);

      await tester.tap(find.byKey(UiKeys.contactNewContactsTab));
      await tester.pumpAndSettle();
      expect(find.byType(TencentCloudChatContactApplication), findsOneWidget);
      expect(find.byType(TencentCloudChatContactBlockList), findsNothing);

      await tester.tap(find.byKey(UiKeys.contactBlockedUsersTab));
      await tester.pumpAndSettle();
      // The previous panel is torn down and the new one mounted.
      expect(find.byType(TencentCloudChatContactBlockList), findsOneWidget);
      expect(find.byType(TencentCloudChatContactApplication), findsNothing);

      await tester.tap(find.byKey(UiKeys.contactNewContactsTab));
      await tester.pumpAndSettle();
      expect(find.byType(TencentCloudChatContactApplication), findsOneWidget);
      expect(find.byType(TencentCloudChatContactBlockList), findsNothing);
    },
  );
}
