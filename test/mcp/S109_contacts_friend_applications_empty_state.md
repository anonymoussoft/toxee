# S109 — Contacts: friend-applications EMPTY state

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=any friendApplications=none`
**Harness mode**: peerHarness=none — the empty friend-applications surface is single-instance and hermetically renderable; no peer is needed to render "no pending applications". (`contact_application_anchors_test.dart:64-79` already pumps `TencentCloudChatContactApplicationList(applicationList: [])` and finds the empty key + "No new application" text.)
**Promotion target**: L1 WidgetTester (surface proven renderable — the existing `test/ui/contact/contact_application_anchors_test.dart` finds `UiKeys.contactApplicationsListEmpty` with an empty list). This scenario is the L3 mirror that drives the real Contacts → New Contacts route and asserts the empty key under live conditions.
**Status**: spec-only (L1 WidgetTester gate owed; surface proven renderable by `contact_application_anchors_test.dart`). Not yet driven on a live bundle.

## Precondition
- One account A logged in, plaintext, sidebar Online (poll 60s)
- **No pending friend applications**: `l3_dump_state.friendApplicationCount == 0` and `friendApplications[] == []` (`l3_debug_tools.dart:3604-3608`). For a freshly registered account this is the natural state; otherwise pre-flight by accepting/declining any pending entries (S26/S27) or use a fresh profile.
- `Prefs.dismissed_friend_applications` may be non-empty — that pref only suppresses already-seen entries; the empty STATE asserted here is `getFriendApplications()` returning none, not a filtered view.
- Debug bundle built with `--dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`)
2. `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab` (`contact_new_contacts_tab`); wait ~500ms (mobile pushes `TencentCloudChatContactApplication`; desktop swaps the right pane)
3. `fmt_semantic_snapshot` → record label `S109_applications_empty`

## Assertions
- A1 (primary): the Step-2 snapshot contains the keyed empty-state widget `contact_applications_list_empty` (`tencent_cloud_chat_contact_application_list.dart:45` — the `Center > Container(key: ValueKey('contact_applications_list_empty'))` branch taken when `widget.applicationList.isEmpty`)
- A2: the empty-state widget contains the localized "no new application" text (`tL10n.noNewApplication`, `tencent_cloud_chat_contact_application_list.dart:47`; the English string is `"No new application"` as asserted in `contact_application_anchors_test.dart:75`)
- A3 (data ground-truth): `l3_dump_state.friendApplicationCount == 0` and `friendApplications[]` is empty (`l3_debug_tools.dart:3604-3608`) — confirms the empty UI reflects an empty queue, not a render glitch
- A4: no application rows present — `find` for any `contact_application_item:` key returns nothing in the Step-2 snapshot
- A5: the New-Contacts badge is absent/zero — `_applicationUnreadCount` drives the tab's `getUnreadCount()` (`tencent_cloud_chat_contact_tab.dart:36-42`); with zero applications there is no count bubble
- A6: `official.get_runtime_errors({})` empty vs Step-0 baseline

## Notes
- L3-pin reason: NONE — this is an L1 WidgetTester candidate; `contact_application_anchors_test.dart:64-79` already proves the exact key + text render with `applicationList: []`. The L3 form only adds "drive the real Contacts route and confirm the live `getFriendApplications()`-empty path lands on this widget". Promote by extending the hermetic test to pump the parent route, or leave it as the cheaper widget-level gate it already is.
- Key status verified: `contact_applications_list_empty` at `tencent_cloud_chat_contact_application_list.dart:45` (`ValueKey` on the empty-branch `Container`). The empty branch is selected by `widget.applicationList.isNotEmpty ? ListView : Center(... empty key ...)` at `:34`.
- Sibling distinction: S26/S27 assert the NON-empty list (an application row surfaces, then accept/decline). S109 asserts the inverse — the empty state when no applications exist. The same `contact_new_contacts_tab` entry leads to both; the list contents differ.
- Gotcha: `dismissed_friend_applications` filtering happens at the Dart layer before `getFriendApplications` returns (S27 Notes); for a true empty assertion, ensure no C++ `pending_applications_` entry is merely being hidden — `l3_dump_state.friendApplicationCount == 0` (A3) is the unambiguous ground-truth, snapshot-only could be a filtered view. Wait ~500ms after the tab tap for the route/pane animation (F14).
