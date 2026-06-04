# S104 — Sidebar user-avatar tap → opens self-profile

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK) window=default`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate (REAL_UI_GATES recipe §47 — `MaterialApp` + `AppLocalizations`/`TencentCloudChatLocalizations` delegates + `TencentCloudChatIntl().init`). `showSelfProfile` is already invoked from a `WidgetTester` harness in `test/ui/profile_edit_persists_to_account_list_test.dart:81-92` (via a test button, not the sidebar `InkWell`). Promote by pumping the real sidebar `_UserAvatar` (`buildSidebar`) and `tester.tap(find.byKey(UiKeys.sidebarUserAvatar))`, then asserting `find.byKey(UiKeys.profileEditToggle)` (or `profileToxIdSelectableText`) `findsOneWidget`. The async Tox-ID resolve in `_openProfile` needs a pumped future, hence the L1 (not pure-unit) layer.
**Status**: spec-only (L1 WidgetTester gate owed — recipe above). No marionette-driven runnable gate; there is no `l3_dump_state` "which page is open" field, so this is asserted purely via the snapshot presence of profile widgets/keys.

## Precondition
- Account A signed in, plaintext profile, HomePage mounted (sidebar visible).
- The sidebar `_UserAvatar` `InkWell` is keyed `sidebar_user_avatar` (`UiKeys.sidebarUserAvatar`, `lib/ui/settings/sidebar.dart:400`); `onTap: () => _openProfile(context)` (`:401`).
- `_openProfile` (`sidebar.dart:354-362`) calls `showSelfProfile(...)` which resolves the real Tox ID (`Prefs.getCurrentAccountToxId()`, falling back to `service.accountKey` on the rare login race, `sidebar.dart:55-59`) and builds `ProfilePage(isEditable: true, …)` (`sidebar.dart:62-66`) inside a desktop `Dialog` or a mobile fullscreen `MaterialPageRoute`.
- `MCP_BINDING=marionette`.

## UI Driver
1. Baseline: `official.get_runtime_errors({})`; snapshot HomePage and confirm `UiKeys.sidebarUserAvatar` is present and NO `UiKeys.profileEditToggle` / `profile_tox_id_selectable_text` (profile not yet open).
2. `marionette.tap` `UiKeys.sidebarUserAvatar` (`sidebar_user_avatar`).
3. Poll the snapshot ≤2s for the profile surface to mount.

## Assertions
- A1 (primary): after Step 2, the snapshot contains the profile widgets — specifically `UiKeys.profileEditToggle` (`profile_edit_toggle`, only present because `isEditable == true`, `profile_header.dart:106-108`) AND `UiKeys.profileToxIdSelectableText` (`profile_tox_id_selectable_text`, `profile_edit_fields.dart:340`, the full 76-hex id panel). Presence of these keys is the proof the self-profile mounted (there is no dump-state page field).
- A2: the rendered `profile_tox_id_selectable_text` value matches `Prefs.getCurrentAccountToxId()` (cross-check the resolved identity — `EXPECTED_TOXID` from `defaults read com.toxee.app 'flutter.current_account_tox_id'`); guards the `showSelfProfile` Tox-ID resolve from regressing to the `FlutterUIKitClient` placeholder.
- A3: the displayed nickname in the profile header matches `Prefs.getNickname()` (`flutter.self_nickname`) — confirms `ProfilePage` got the live identity, not a stale/empty one.
- A4: the `profileToxIdCopyButton` (`profile_tox_id_copy_button`) is also present (the read-only ProfileToxIdSection rendered fully) — belt-and-suspenders on A1.
- A5: the profile surface is dismissable — desktop: a close-`X` `IconButton` is present (`sidebar.dart` Dialog top-right); mobile: `marionette.press_back_button()` pops the route. After dismiss, the snapshot returns to HomePage (no `profileEditToggle`).
- A6: `official.get_runtime_errors({})` empty vs the Step-1 baseline (catches an async-resolve exception in `_openProfile` / `showSelfProfile`).

## Notes
- L3-pin reason: none intrinsic — this is L1-promotable (the avatar→profile open is pure widget + a pumped async future). It's spec-only today; the recipe in the Promotion target is the owed gate.
- Key status (verified): `sidebarUserAvatar` @ `sidebar.dart:400`; `profileEditToggle` @ `profile_header.dart:108`; `profileToxIdSelectableText` @ `profile_edit_fields.dart:340`. All shipped.
- Sibling distinction: S8/S101/S102/S103 all START from the open profile; S104 isolates the ENTRY POINT — the sidebar-avatar→profile navigation itself, which the others assume. S3 touches the same `_UserAvatar` node but for the account-switch label refresh, not the open-profile tap.
- Gotcha: no `l3_dump_state` field reports "profile page open" — the ONLY honest assertion is snapshot presence of the profile keys (A1). Don't fabricate a route/page dump field.
- Mobile parity: the avatar `InkWell` + `showSelfProfile` are shared Dart; the only platform fork is Dialog (desktop) vs fullscreen route (mobile), both in `sidebar.dart`. A5's dismiss differs (close-`X` vs back button); the open + identity assertions (A1–A4) are identical.
