# S11 — Open a conversation from the chat list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L2 candidate. The conversation row now has a stable runtime key via `UiKeys.conversationListTile("c2c_<toxF>")`; promotion still depends on exercising the per-conversation mount hermetically against the live UIKit overlay + master-detail layout.
**Status**: covered (wide / desktop variant)

Prerequisite for all S12–S25 messaging scenarios.

## Precondition
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — restores `~/Library/Containers/com.toxee.app/Data/...` (profiles + account_data) + Prefs (`flutter.account_list`, `flutter.current_account_tox_id`, `flutter.local_friends_<prefix>`, scoped per-account keys) from cached tarball at `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst`. The restore wipes existing toxee state.
- **Seeded state**: after restore, the active account is `echo_seeded_test` (auto-login enabled); 1 friend (the echo peer) is in the contact list with status "Offline" (since the bot isn't running for seeded scenarios); chat history contains 3 ping/pong message pairs.
- **Cache miss**: if `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst` doesn't exist on this machine, restore auto-calls `regen_echo_peer_seed.sh` to populate. Generation takes a few minutes (launches Toxee, drives via marionette, snapshots). Subsequent restores are fast.
- **Echo peer NOT running**: the bot is intentionally offline during this scenario — the friend appears Offline. Tests that depend on peer being Online belong in `peerHarness=echo_live` scenarios.
- Fixture A+friend1+conv: A signed in, plaintext profile, one friend F seeded in `friends.json`, ≥1 message in `messages/c2c_<toxF>.json` (so conversation row exists on first paint)
- Friend F does NOT need to be reachable
- macOS desktop wide breakpoint (`shouldShowMasterDetail == true`)
- `MCP_BINDING=marionette`

## Driver
1. Snapshot, poll up to 60s for sidebar `_UserAvatar` `<nicknameA>\nOnline`; capture runtime-errors baseline
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); no-op on cold start (`_index=0`)
3. Snapshot → find conversation row whose label contains `<friendName>` + last-message preview
4. Tap the row: prefer `marionette.tap({ key: "conversation_list_item:c2c_<toxF>" })` via `UiKeys.conversationListTile("c2c_<toxF>")`. Semantic-action (`fmt_tap_widget`) or label-match tap remains the fallback for fixtures that do not know `<toxF>` ahead of time.
5. Re-snapshot ≤2s; verify chat panel mounted on right pane
6. Poll log ≤5s for `setActivePeer(c2c_<toxF>)`

## Assertions
- A2: snapshot after Step 2 contains a conversation row labeled with `<friendName>` + preview
- A3: snapshot after Step 4 contains `TencentCloudChatMessageHeader` whose label includes `<friendName>` (driven by `ToxeeMessageHeaderInfo`, `home_page_bootstrap.dart:417-424`)
- A4: snapshot shows ≥1 message bubble whose label matches a pre-seeded message text (or empty-state placeholder for empty-history variant)
- A5: snapshot includes a "text field" semantic node inside the chat panel subtree (message input)
- A6: log contains `setActivePeer(c2c_<toxF>)` (toxee handler at `home_page_bootstrap.dart:545-560`)
- A7: `official.get_runtime_errors({})` equals Step-1 baseline
- A8 (wide): conversation list still visible on left pane after row tap (master-detail; UIKit doesn't unmount the list)
- Negative grep: `messageNoChatBuilder fired` must NOT appear after Step 4 (would mean `currentConversation` wasn't set)

## Notes
- Empty conversations (zero history) don't auto-render rows — toxee derives the list from `messages/*` + `friends.json`; seed ≥1 message per friend you want a row for.
- Phone-S11 variant (narrow / push-route) is a separate follow-up.
- `_messageWidgetKeyCounter` bump (`home_page_bootstrap.dart:188-212`) is post-frame; chaining rapid conversation opens needs ≥1 frame between taps (non-issue at MCP roundtrip speeds).
- `onTapConversationItem` returns `false` intentionally so UIKit's default route push/pane swap proceeds.
