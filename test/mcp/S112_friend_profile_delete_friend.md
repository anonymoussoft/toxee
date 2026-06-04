# S112 — Friend profile: delete-friend button

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed, with history+optional avatar)`
**Harness mode**: peerHarness=echo_seeded (single-instance unfriend — `tox_friend_delete` only mutates A's local state, so F may be offline; a live-twin two-process run is the stronger variant)
**Promotion target**: **L2 candidate once harnessed** (per S28's promotion target — the flow crosses UIKit profile body + Tim2Tox platform + FFI delete + FakeIM steady-state poll diff, all L2-reachable, no live DHT). The real-UI tap on the destructive row is the L3/L2 surface.
**Status**: covered by S28's data + behavioral assertions (delete-friend → friend leaves `friends[]` / `Prefs.local_friends`). NO `l3_*` delete-friend tool exists, so the data-half is the S28 manual/seeded path or a two-process run — NOT a hermetic runner gate. The real-UI tap on `user_profile_delete_friend_button` is L3 / L2 candidate.

> Real-UI anchor for S28. S28 already documents the full delete flow and behavioral assertions; S112 pins the exact button key + records the absence of an `l3` delete-friend tool so reviewers don't expect a hermetic gate.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline), 3 ping/pong history pairs. Restore wipes existing state; cache miss auto-regenerates.
- Account A logged in, plaintext, sidebar Online (poll ≤60s).
- `Prefs.local_friends_<toxA_prefix16>` contains `<toxF>`; `Prefs.friend_nickname_<toxF>_<toxA_prefix16>` set.
- Optional avatar at `<accountDataRoot>/avatars/<toxF>.png` + `avatar_hash_<toxF>` / `friend_avatar_path_<toxF>` Prefs (exercises `FriendAssetCleanup`).
- F may be offline — `tox_friend_delete` updates A's local state immediately; the FakeIM 5s steady-state poll emits `topicFriendDeleted`.
- The delete-friend row is the LOWER destructive row (`tL10n.delete` / "删除"), rendered ONLY when F is in `contactList` (the `if (friendIDList.contains(...))` guard at tencent_cloud_chat_user_profile_body.dart:723). It is NOT the upper clear-history row (`tL10n.deleteAllMessages`, S111).

## Executable Driver

No hermetic runner gate exists. `grep -n "delete_friend\|removeFriend" lib/ui/testing/l3_debug_tools.dart` returns no tool: the registered friend mutations are `l3_set_friend_remark`, `l3_set_blocked`, `l3_accept_friend_request`, `l3_refuse_friend_request` (l3_debug_tools.dart:193-194) — there is no `l3_remove_friend`/`l3_delete_friend`. The data-half is therefore either (a) the S28 seeded manual path (tap the row, observe `friends[]` / Prefs diff), or (b) a two-process Fixture C run where A unfriends a live twin B. Neither is a single-command JSON gate.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`).
2. Tap F's row `marionette.tap(UiKeys.contactListTile(<toxF>))` (`contact_list_item:<toxF>`) → push `TencentCloudChatUserProfile`. Confirm `UiKeys.userProfileFriendNameText` shows F's name.
3. Tap `UiKeys.userProfileDeleteFriendButton` (`user_profile_delete_friend_button`). It is a `GestureDetector` (tencent_cloud_chat_user_profile_body.dart:731-734) — use marionette key tap (`fmt_tap_widget` may no-op without `Semantics.onTap`). It calls `onDeleteContact` → `deleteFromFriendList([<toxF>], V2TIM_FRIEND_TYPE_BOTH)`.
4. **No confirmation dialog appears today** (the GestureDetector calls `onDeleteContact` directly; no adaptive dialog in `onDeleteContact`, lines 659-691). `Navigator.of(context).pop()` fires only on success (line 688). If a future toxee patch adds a confirm UX, add a `user_profile_delete_friend_confirm_button` key (per S28 Notes) and an extra tap — do NOT overload the clear-history confirm key.
5. Wait ≤15s for the FakeIM 5s steady-state poll diff to detect the missing friend and emit `topicFriendDeleted` (async; don't assert immediately after tap).

## Assertions
- A1 (pre-delete, control): `l3_dump_state.friends[]` contains `<toxF>`; `friendCount` ≥ 1; F's row present in the Contacts tree.
- A2 (primary): post-delete, `l3_dump_state.friends[]` no longer contains `<toxF>` and `friendCount` drops by 1; `Prefs.local_friends_<toxA_prefix16>` no longer contains normalized `<toxF>` (the S28 A5 discriminator vs delete-conversation-only).
- A3: F absent from BOTH the Contacts AND Chats trees in a `fmt_semantic_snapshot` after the poll.
- A4: log emits `onUserNotificationEvent` with `tL10n.deleteFriendSuccess`; ordered markers `deleteFromFriendList` → `[FfiChatService] clearC2CHistory:` → `topicFriendDeleted` → `FakeFriendDeleted` → `[FakeChatDataProvider] Removed conversation c2c_` (S28 A9/A11/A12).
- A5 (avatar cleanup, if pre-existing): `Prefs.avatar_hash_<toxF>` / `friend_avatar_path_<toxF>` unset and the on-disk avatar file gone (`FriendAssetCleanup`).
- A6: `official.get_runtime_errors({})` empty vs the Step-1 baseline; no `FATAL`/`terminate called`.
- Negative grep at >15s post-tap: `[FakeIM] _emitContacts ... friends=[...<toxF>...]` MUST NOT match.

## Notes
- L3/L2: S28 already names this an L2 candidate (no live DHT — `tox_friend_delete` is local). S112 only adds the exact key anchor + the honest "no `l3` delete-friend tool" fact; defer the executable-gate framing to S28.
- Key verified: `user_profile_delete_friend_button` @ tencent_cloud_chat_user_profile_body.dart:733 (raw `ValueKey`, rendered only when F ∈ `contactList`).
- Sibling distinction: S112 = lower delete-friend row (`tL10n.delete`); S111/S28-upper = clear-history (`tL10n.deleteAllMessages`). Distinct anchors avoid the row-order trap.
- Destructive + NO confirm dialog today: the tap unfriends immediately (no second-step gate). This is intentionally noted so a future confirm-UX patch adds its OWN `user_profile_delete_friend_confirm_button` key rather than reusing S111's clear-history confirm.
- After this scenario the seeded fixture is "dirty" (its only friend is gone) — re-run `restore_echo_peer_seed.sh` before any scenario that needs the seeded friend.
- Mobile parity: the delete-friend row lives in the SHARED `tencent_cloud_chat_user_profile_body.dart` (no platform split), so iOS/Android hit the same key and the same no-confirm behavior — covered via the same anchor.
