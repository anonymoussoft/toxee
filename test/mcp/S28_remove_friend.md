# S28 — Remove a friend

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F with history+optional avatar)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: **L2 candidate once harnessed.** Flow crosses UIKit profile body + Tim2Tox platform + FFI delete + FakeIM steady-state poll diff — all L2-reachable (no live DHT required; F may be offline because `tox_friend_delete` only updates local state). The 15s FakeIM poll wait can be replaced by a deterministic stub-driven event in L2. Sibling of S20 (deletes only the conversation, friendship intact); the discriminator is friend list contents.
**Status**: covered

## Precondition
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — restores `~/Library/Containers/com.toxee.app/Data/...` (profiles + account_data) + Prefs (`flutter.account_list`, `flutter.current_account_tox_id`, `flutter.local_friends_<prefix>`, scoped per-account keys) from cached tarball at `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst`. The restore wipes existing toxee state.
- **Seeded state**: after restore, the active account is `echo_seeded_test` (auto-login enabled); 1 friend (the echo peer) is in the contact list with status "Offline" (since the bot isn't running for seeded scenarios); chat history contains 3 ping/pong message pairs.
- **Cache miss**: if `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst` doesn't exist on this machine, restore auto-calls `regen_echo_peer_seed.sh` to populate. Generation takes a few minutes (launches Toxee, drives via marionette, snapshots). Subsequent restores are fast.
- **Echo peer NOT running**: the bot is intentionally offline during this scenario — the friend appears Offline. Tests that depend on peer being Online belong in `peerHarness=echo_live` scenarios.
- Account A logged in, plaintext profile, sidebar Online (poll up to 60s)
- `Prefs.local_friends:<toxA>` contains `<toxF>`; `Prefs.friend_nickname:<toxF>` set
- At least one persisted c2c message in both directions for F (so the history-cleanup assertion exercises something)
- Optional: avatar file at `<accountDataRoot>/avatars/<toxF>.png` + `avatar_hash_<toxF>` / `friend_avatar_path_<toxF>` prefs (exercises `FriendAssetCleanup`)
- F may be offline — `tox_friend_delete` updates A's local state immediately

## Driver
1. `marionette.tap({ key: "sidebar_contacts_tab" })`
2. Locate F's row by `<nicknameF>`; `fmt_tap_widget` to push `TencentCloudChatUserProfile`
3. Prefer `UiKeys.userProfileDeleteFriendButton` (`user_profile_delete_friend_button`) for the lower red row labeled exactly `l10n.delete` ("删除"/"Delete") — NOT `user_profile_clear_history_button` / `l10n.deleteAllMessages` ("清除聊天记录"/"Delete all messages"). Disambiguation matters — the upper row triggers history-clear, not unfriend.
4. Tap. NO confirmation dialog appears in current upstream code (`tencent_cloud_chat_user_profile_body.dart:616-648`). Navigator pops on success.
5. Wait up to 15s for FakeIM 5s steady-state poll diff to detect missing friend and emit `topicFriendDeleted`

## Assertions
- A1: pre-delete — F's nickname in Contacts semantic tree
- A2: pre-delete — `c2c_<toxF>` row in Chats tab
- A3 (primary): post-delete — F absent from BOTH Contacts AND Chats trees
- A4: history store for `c2c_<toxF>` removed (filesystem diff under `<accountDataRoot>`)
- A5 (primary discriminator vs S20): `Prefs.local_friends:<toxA>` no longer contains `<toxF>`
- A6: `Prefs.avatar_hash_<toxF>` and `Prefs.friend_avatar_path_<toxF>` unset (if pre-existing)
- A7: on-disk avatar file gone (if pre-existing)
- A9: log emits `onUserNotificationEvent` with `tL10n.deleteFriendSuccess`
- A10: `official.get_runtime_errors({})` empty vs Step 0 baseline
- A11: log contains `[FfiChatService] clearC2CHistory:` with `<toxF>`
- A12: log contains `[FakeChatDataProvider] Removed conversation c2c_<toxF> ... via FakeFriendDeleted event`
- Log markers in order: `deleteFromFriendList` → `[FfiChatService] clearC2CHistory:` → `topicFriendDeleted` → `FakeFriendDeleted` → `[FakeChatDataProvider] Removed conversation c2c_` → `FriendAssetCleanup`
- Negative grep at >15s post-tap: `[FakeIM] _emitContacts ... friends=[...<toxF>...]` MUST NOT match

## Notes
- After this scenario, the seeded fixture is "dirty" — the only friend (the echo peer) has been removed, leaving an empty contact list. The next scenario that depends on the seeded friend being present MUST re-run `bash tool/mcp_test/restore_echo_peer_seed.sh` to reset state before proceeding.
- Cleanup is async (FakeIM 5s poll); don't assert immediately after tap. Allow 15s for cold-machine slack.
- The two adjacent destructive rows now have distinct anchors: `user_profile_clear_history_button` (upper) and `user_profile_delete_friend_button` (lower). If a future confirm dialog is added for delete-friend, add `user_profile_delete_friend_confirm_button` rather than overloading the clear-history confirm key.
- No confirmation dialog today; if a toxee patch adds one (consistent with destructive-action UX), add a `user_profile_delete_friend_confirm_button` key and an extra tap step
- Partial key status: `contact_list_tile:<toxId>`, `user_profile_delete_friend_button`, `user_profile_clear_history_button`, and `user_profile_clear_history_confirm_button` are now available. A future delete-friend confirm UX would still need its own confirm-button anchor.
