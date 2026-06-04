# S110 — Contacts: Group-Notifications tab listing

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any groupApplications=none(empty surface) | groupApplications=1(live content needs a peer invite)`
**Harness mode**: peerHarness=none for the TAB + empty surface (single-instance, hermetic) — but **live group-notification CONTENT requires a real peer invite** (two toxees), so populated-list assertions inherit the Fixture C constraint. Group invites/applications are native-residual the same way friend `pending_applications_` is.
**Promotion target**: L1 WidgetTester candidate for the empty surface (the `group_notification` tab key + the `TencentCloudChatContactGroupApplicationList` empty render are hermetic, analogous to `contact_application_anchors_test.dart`'s coverage of the new-contacts trio). Live content is **L3-pinned** (real inbound group invite over the DHT).
**Status**: surface spec-only (L1 candidate — no hermetic test pumps `TencentCloudChatContactGroupApplicationList` yet; one is owed). Live group-notification content L3-pinned and **blocked on Fixture C** for a populated list. Cross-ref S47 (group-invite inbound data path) and S81 for the invite-residual context.

## Precondition
- One account A logged in, plaintext, sidebar Online (poll 60s)
- Empty-surface arm: no pending group notifications — the tab still renders and opens its (empty) panel
- Populated arm (L3, Fixture C): a second toxee B has sent A a group invite/join-request over a live DHT (the S47 inbound path); this state is native-residual, no on-disk inject
- Debug bundle built with `--dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`)
2. `marionette.tap({ key: "contact_group_notifications_tab" })` via `UiKeys.contactGroupNotificationsTab` (`contact_group_notifications_tab`); wait ~500ms (mobile `Navigator.push`-es `TencentCloudChatContactGroupApplicationList`; desktop sets `_desktopModule` + `_title = tL10n.groupChatNotifications`)
3. `fmt_semantic_snapshot` → record label `S110_group_notifications_panel`

## Assertions
- A1 (surface, primary): the Step-2 snapshot shows the Group-Notifications panel mounted — AppBar/title `tL10n.groupChatNotifications` (desktop sets it at `tencent_cloud_chat_contact.dart:201`/`:204`; mobile pushes the route at `:282-288`) and the panel widget is `TencentCloudChatContactGroupApplicationList`
- A2 (surface): the `contact_group_notifications_tab` key is findable in the Contacts-list snapshot before the tap (same trio proven by `contact_application_anchors_test.dart:60`)
- A3 (empty arm): with no pending group notifications, the panel renders its empty/zero-item state (no group-application rows); no runtime error
- A4 (populated arm, L3 / Fixture C): after B's group invite reaches A, the panel lists a group-application row for the invited group; tapping it opens the group-application detail (the group-invite accept path; cross-ref `UiKeys.groupInviteAcceptButton(<groupId>)` = `group_invite_accept_button:<groupId>` and S47)
- A5: `official.get_runtime_errors({})` empty vs Step-0 baseline

## Notes
- L3-pin reason: the TAB and its empty panel are hermetic (L1 candidate), but POPULATING the list needs a real inbound group invite from a second toxee — group notifications are native-residual (no on-disk inject), the same shape as friend `pending_applications_`. The S47/S81 group-invite residual is the data path; this scenario owns only the Group-Notifications TAB rendering.
- Key status verified: `contact_group_notifications_tab` at `tencent_cloud_chat_contact_tab.dart:48` (mobile `defaultBuilder`, GestureDetector) / `:112` (desktop `desktopBuilder`, InkWell), keyed by `switch (widget.item.id) { 'group_notification' => ValueKey('contact_group_notifications_tab') }`. The panel it opens is `TencentCloudChatContactGroupApplicationList` (`tencent_cloud_chat_contact.dart:205` desktop / `:287` mobile) — that list widget has **no documented stable empty-state key** of its own (unlike the friend-application list's `contact_applications_list_empty`); A3 asserts by panel-mounted + zero-rows, not by a dedicated empty key. If a future patch adds `contact_group_applications_list_empty`, tighten A3.
- Sibling distinction: S106 navigates ALL three tabs (asserts each panel mounts); S110 drills into Group-Notifications specifically and adds the populated-list (L3) arm. S47 owns the inbound group-invite DATA path; S110 owns the Contacts-tab UI surface that displays it.
- Gotcha: mobile pushes a full route (must `press_back_button` to leave); desktop swaps the pane. The mobile Contacts list ALSO has a `groups` tab (id `groups`, `tencent_cloud_chat_contact.dart:293`) with no automation key — do not confuse it with `group_notification`. Wait ~500ms after the tab tap for the route/pane animation (F14).
