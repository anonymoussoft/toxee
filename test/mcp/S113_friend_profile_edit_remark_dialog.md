# S113 — Friend profile: edit-remark dialog (full real-UI flow)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed, nickName set, no prior remark)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: **L1 WidgetTester candidate** — the modify-remark dialog is a pure UIKit state machine (open → `TextField.onChanged` accumulates → confirm calls `_onChangeFriendRemark`), drivable behind a constructor seam with a stub `setFriendInfo`/Prefs; the only L3-only bit is the real `SharedPreferencesAdapter.setFriendRemark` round-trip, which L2 covers. Sibling of S30 (data-set path) and S28/S111/S112 (same profile-body entry).
**Runner gate (data-half)**: `tool/mcp_test/scenarios/l3_friend_remark_toggle.json`
**Status**: covered (data-half gate exists — `l3_friend_remark_toggle` proves `friends[].remark` set/clear round-trip; the real-dialog enter-text + confirm tap is L3 / L1 WidgetTester candidate, not yet a runnable UI gate)

> Real-dialog upgrade of S30. S30's runner gate drives `l3_set_friend_remark` directly; S113 drives the actual pencil-button → `AlertDialog` → `TextField` → confirm flow so the dialog state machine and the name-text live update are exercised through real taps.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline). Restore wipes existing state; cache miss auto-regenerates.
- Account A logged in, plaintext, sidebar Online (poll ≤60s).
- `Prefs.friend_nickname_<toxF>_<toxA_prefix16>` set (the unambiguous "before" name shown when no remark exists — the profile body falls back to `nickName` at tencent_cloud_chat_user_profile_body.dart:209-211).
- `Prefs.friend_remark_<toxF>_<toxA_prefix16>` MUST be absent pre-test so A2/A3 observe a fresh write, not a no-op. Verify: `defaults read com.toxee.app "flutter.friend_remark_<toxF>_<toxA_prefix16>" 2>&1 | grep "does not exist"`.
- Scoped key uses FIRST 16 chars of `<toxA>` (`Prefs._scopedKey`).
- The pencil button renders ONLY when F ∈ `contactList` (the `if (friendIDList.contains(...))` guard at tencent_cloud_chat_user_profile_body.dart:237).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart --only L3-friend-remark-toggle
```

`tool/mcp_test/scenarios/l3_friend_remark_toggle.json` is the hermetic data-half: it waits for the friends list to be free of a `L3rmk-{{nonce}}` remark, sets that nonce remark via `l3_set_friend_remark`, asserts `state{field: friends, contains: L3rmk-{{nonce}}}`, then clears it (empty string) and asserts `state{field: friends, notContains: L3rmk-{{nonce}}}`. This proves the account-scoped `Prefs.setFriendRemark` round-trip (distinct from the Tox `nickName`). It does NOT open the `AlertDialog` or type into the `TextField` — that real-dialog leg is the S113 UI Driver below and has no runnable UI gate yet.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`).
2. Tap F's row `marionette.tap(UiKeys.contactListTile(<toxF>))` (`contact_list_item:<toxF>`) → push `TencentCloudChatUserProfile`. Confirm `UiKeys.userProfileFriendNameText` (`user_profile_friend_name_text`) reads F's nickName (the "before" label).
3. Tap `UiKeys.userProfileEditRemarkButton` (`user_profile_edit_remark_button`) — the `FloatingActionButton.small` pencil at tencent_cloud_chat_user_profile_body.dart:240-241. It calls `changeFriendRemark`.
4. The dialog mounts at `UiKeys.userProfileModifyRemarkDialog` (`user_profile_modify_remark_dialog`, AlertDialog title `tL10n.modifyRemark` "Modify remark"/"修改备注", line 172).
5. `marionette.enter_text(UiKeys.userProfileModifyRemarkTextField, "<new remark, unique nonce>")` (`user_profile_modify_remark_text_field`, line 175 — autofocus `TextField`; its `onChanged` accumulates into the local `remark` var, line 178-180).
6. Tap `UiKeys.userProfileModifyRemarkConfirmButton` (`user_profile_modify_remark_confirm_button`, the `tL10n.confirm` `TextButton` at line 191) → calls `_onChangeFriendRemark(remark)` then `Navigator.pop`. `_onChangeFriendRemark` is the path that writes `setFriendInfo` → `SharedPreferencesAdapter.setFriendRemark`.

## Assertions
- A1 (pre-edit, control): `UiKeys.userProfileFriendNameText` shows F's `nickName`; `l3_dump_state.friends[]` entry for `<toxF>` has `remark == ""`.
- A2 (primary persistence): after confirm, `l3_dump_state.friends[]` entry for `<toxF>` has `remark` == the entered nonce — the SAME observable the data-half gate asserts (`state{field: friends, contains: …}`, l3_friend_remark_toggle.json:13).
- A3 (live name update): `UiKeys.userProfileFriendNameText` now reads the new remark (the body recomputes `friendRemark` from `getFriendRemark`, line 209-211) — the S30 A1 observable.
- A4 (Prefs round-trip): `Prefs.friend_remark_<toxF>_<toxA_prefix16>` literal equals the entered nonce (the on-disk write `l3_set_friend_remark` and the dialog confirm share).
- A5 (nickName untouched): `Prefs.friend_nickname_<toxF>_<toxA_prefix16>` UNCHANGED — the alias is local-only, never overwrites the peer's nickName (S30 A4).
- A6 (no wire traffic): NO `tox_friend_send_*` log line during the dialog flow; NO `no preferences service available` (that would mean the adapter is unwired). Optionally `setFriendInfo` followed by `code: 0` (S30 A7).
- A7: `official.get_runtime_errors({})` empty vs the Step-1 baseline.

## Notes
- L1/L3: the dialog state machine is L1-mountable (S30 already names the data-set path hermetic via the runner gate); the on-disk Prefs write is L2. S113 is the real-dialog tap upgrade, not a new executable gate.
- Keys verified: `user_profile_edit_remark_button` @ tencent_cloud_chat_user_profile_body.dart:241; `user_profile_modify_remark_dialog` @ :172; `user_profile_modify_remark_text_field` @ :175; `user_profile_modify_remark_confirm_button` @ :191; `user_profile_friend_name_text` @ :227. All raw `ValueKey`.
- Sibling distinction: S30 = the `l3_set_friend_remark` data round-trip (+ a documented conversation-header B-block gap); S113 = the real pencil→dialog→TextField→confirm flow. The cancel path (line 183-187, `Navigator.pop` only, no `_onChangeFriendRemark`) is an S30b variant, NOT asserted here.
- Empty-string confirm DELETES the alias (`shared_prefs_adapter.dart` `remove(key)` on empty) — a clear-alias B-variant; the happy path here sets a non-empty nonce.
- Mobile parity: the pencil button + modify-remark dialog live in the SHARED `tencent_cloud_chat_user_profile_body.dart` (no platform split); iOS/Android hit the same keys, so this scenario covers mobile via the same anchors. `enter_text` on the autofocus `TextField` works the same across platforms.
