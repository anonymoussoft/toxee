# S106 — Contacts: sub-tab navigation (New Contacts / Group Notifications / Blocked Users)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any window=default friends=any`
**Harness mode**: peerHarness=none — the three sub-tabs and the panels they open are single-instance and hermetically renderable; no second Tox endpoint is required to drive navigation. (`contact_application_anchors_test.dart` proves the three tab keys render under `TestWidgetsFlutterBinding`.)
**Promotion target**: L1 WidgetTester (surface proven renderable — the existing `test/ui/contact/contact_application_anchors_test.dart` already finds all three tab keys in a `_buildTabHarness()`; this scenario is the L3 mirror that also asserts the panel mounts on real taps). No live-DHT dependency.
**Status**: spec-only (L1 WidgetTester gate owed; surface proven renderable by `contact_application_anchors_test.dart`). Not yet driven on a live bundle.

## Precondition
- One account A logged in, plaintext, sidebar Online (poll `<nick>\nOnline` ≤60s) — `friends`/`blockedUsers`/`friendApplications` state is "don't care" for navigation; the tabs render regardless of contents.
- Debug bundle built with `--dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- Desktop vs mobile path differ and must be distinguished when asserting (see Notes): desktop `desktopBuilder` swaps the right pane via `setState` (`tencent_cloud_chat_contact.dart:189-221`); mobile `defaultBuilder` `Navigator.push`-es a new route per tab (`tencent_cloud_chat_contact.dart:269-311`).

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`)
2. `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab` (`contact_new_contacts_tab`); wait ~500ms for the route/pane swap
3. `fmt_semantic_snapshot` → capture the New-Contacts panel (`TencentCloudChatContactApplication`) — record label `S106_new_contacts_panel`
4. On mobile: `marionette.press_back_button` to pop the route; on desktop: skip (pane is swapped in place)
5. `marionette.tap({ key: "contact_group_notifications_tab" })` via `UiKeys.contactGroupNotificationsTab` (`contact_group_notifications_tab`); wait ~500ms
6. `fmt_semantic_snapshot` → capture the Group-Notifications panel (`TencentCloudChatContactGroupApplicationList`) — record label `S106_group_notifications_panel`
7. On mobile: `marionette.press_back_button`; on desktop: skip
8. `marionette.tap({ key: "contact_blocked_users_tab" })` via `UiKeys.contactBlockedUsersTab` (`contact_blocked_users_tab`); wait ~500ms
9. `fmt_semantic_snapshot` → capture the Blocked-Users panel (`TencentCloudChatContactBlockList`) — record label `S106_blocked_users_panel`

## Assertions
- A1: all three tab keys are findable in the Step-1 snapshot — `contact_new_contacts_tab`, `contact_group_notifications_tab`, `contact_blocked_users_tab` (the same trio asserted in `contact_application_anchors_test.dart:60-61`)
- A2: after Step 2, the New-Contacts panel mounts — snapshot contains the AppBar title `tL10n.newContacts` (desktop sets `_title = tL10n.newContacts`, `tencent_cloud_chat_contact.dart:191`) AND either an application row `contact_application_item:<userId>` or the empty key `contact_applications_list_empty` (whichever matches the account's `friendApplications[]`)
- A3: after Step 5, the Group-Notifications panel mounts — title `tL10n.groupChatNotifications` (`tencent_cloud_chat_contact.dart:201`/`204`); `TencentCloudChatContactGroupApplicationList` present
- A4: after Step 8, the Blocked-Users panel mounts — title `tL10n.blockList` (`tencent_cloud_chat_contact.dart:214`/`217`); panel is `TencentCloudChatContactBlockList`, showing rows or `tL10n.noBlockList`
- A5: `l3_dump_state` `blockedUsers[]` count equals the number of rows rendered in the Step-9 Blocked-Users snapshot (cross-checks the panel reflects real state, `l3_debug_tools.dart:3598`)
- A6: `official.get_runtime_errors({})` empty vs the Step-0 baseline

## Notes
- L3-pin reason: NONE for the surface — this is an L1 WidgetTester candidate; the L3 form exists only to validate the panel actually mounts on a real tap in the running app (the hermetic test pumps the tab in isolation, not the full Contacts route swap). Promote by extending `contact_application_anchors_test.dart` to pump the parent `TencentCloudChatContact` and assert each panel mounts after a tab tap.
- Keys verified: `contact_new_contacts_tab`/`contact_group_notifications_tab`/`contact_blocked_users_tab` at `tencent_cloud_chat_contact_tab.dart:47-49` (mobile `defaultBuilder`, GestureDetector) AND `:111-113` (desktop `desktopBuilder`, InkWell) — `switch (widget.item.id)` keys the wrapper per tab id.
- Sibling distinction: S26/S27 tap `contact_new_contacts_tab` only as a step toward accept/decline; S106 is the dedicated navigation test that asserts ALL THREE tabs + their panels. S107 drills into the Blocked-Users tab specifically; S109 into the New-Contacts empty state; S110 into Group-Notifications.
- Gotcha: the mobile path pushes a full route per tab (must `press_back_button` between tabs); the desktop path swaps `_desktopModule` in place (no back). Drive the matching arm for the platform under test.
- Tab wrappers are `GestureDetector`/`InkWell` with `onTap` (no `Semantics.onTap`) → `fmt_tap_widget` may no-op; use marionette key tap. Wait ~500ms after each tap for the route/pane animation (F14, `doc/research/UI_TEST_RUN_FINDINGS.en.md`).
