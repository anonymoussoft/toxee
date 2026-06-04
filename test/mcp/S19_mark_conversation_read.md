# S19 — Mark conversation as read; unread N → 0 → 0 across restart

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded(N=3,unread)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because exercises `BadgeService` → OS dock/launcher (platform-gated; macOS arm64), plus kill+relaunch persistence round-trip
**Status**: covered (default A+F+unread-3; A+F+unread-100 overflow variant optional)

Builds on S11 (open-conversation gesture) and S14 (restart-disk discipline). Locks in the N → 0 → 0 closed loop.

## Precondition
- Fixture A+F+unread-N: A signed in, plaintext profile, friend F in `friends.json`, seeded `chat_history/c2c_<toxF>.json` with N=3 incoming unread messages — every row: `isSelf: false`, `isRead: false`, `fromUserId: <toxF>`, `timestamp` ascending (1716800001000 / 002000 / 003000), `isPending: false`; `lastViewTimestamp: 0` (strictly below earliest msg timestamp so `loadHistory` reconciliation doesn't auto-mask)
- Locale pinned to `en` (semantic label `Unread messages: 3` from `AppLocalizations.unreadMessagesSemantics(3)`) until `sidebarChatsUnreadBadge` key lands
- macOS arm64 (BadgeService is platform-gated — Linux/Windows skip A2/A6/A9 log assertions)
- `MCP_BINDING=marionette`

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`; baseline runtime-errors
2. **Do not open the conversation yet.** Re-snapshot: assert sidebar Chats badge subtree has semantic label `Unread messages: 3`; conversation row shows unread pill. Poll log up to 2s for `[BadgeService] badge written: 3`
3. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`) — usually no-op on cold start
4. Snapshot → find F's row (label includes nickname + unread count)
5. Tap the row by `UiKeys.conversationListTile("c2c_<toxF>")` (`conversation_list_item:c2c_<toxF>`). `fmt_tap_widget` or label-match remains the fallback when the fixture does not know the exact tox ID up front.
6. ≤2s — verify chat panel mounted with `TencentCloudChatMessageHeader` showing `<friendName>` (sanity)
7. Poll log up to 5s for `[BadgeService] badge written: 0` (200ms debounce + ~100ms propagation); re-snapshot
8. (Optional pre-relaunch shell assertion) read `c2c_<toxF>.json` JSON: zero rows with `isSelf==false && isRead==false`; `lastViewTimestamp >= max(msg.timestamp)`
9. `pkill -9 -f "Debug/Toxee.app/Contents/MacOS/Toxee"`; relaunch via `./run_toxee.sh`, reconnect both MCPs
10. **Do not reopen the conversation.** Wait for HomePage (Step 1 polling); snapshot + log check

## Assertions
- A1: Step 2 snapshot — sidebar badge subtree has `Unread messages: 3`; conversation row label includes the unread count
- A2: Step 2 log — `[BadgeService] badge written: 3` within 2s of `\nOnline`
- A3: Step 6 — chat panel mounted with `<friendName>` in header
- A4: log contains `setActivePeer(c2c_<toxF>)` (or any `[FfiChatService]`/`[HomePage]` line with the conversation ID)
- A5: Step 7 snapshot — sidebar Chats badge subtree no longer contains `Unread messages` semantic label (returns `SizedBox.shrink()` at `totalUnreadCount==0`); conversation row no longer shows unread pill
- A6: Step 7 log — `[BadgeService] badge written: 0` within 2s of tap
- A7: on-disk `c2c_<toxF>.json` has zero `isSelf==false && isRead==false` rows
- A8: on-disk `lastViewTimestamp >= max(msg.timestamp)`
- A9 (headline): post-relaunch — same A5 conditions hold on the new session, AND **no** post-relaunch `badge written: N>0` line ever appears (no bounce-back regression)
- A10: `official.get_runtime_errors({})` matches Step-1 baseline across both sessions
- A11 (phone): same A5 check on `bottomNavChatsUnreadBadge` once that key lands
- A12: log contains `[NotificationService] clearConversationGroup(c2c_<toxF>)` from `home_page_bootstrap.dart:202-203`
- Negative grep post-Step-5: `badge written: 3`, `Failed to initialize TIMManager SDK`, `[FfiChatService] saveHistory failed` must NOT appear
- Negative grep post-Step-10: any `badge written: 1`/`2`/`3` (off-by-one or full bounce-back regression)

## Notes
- The real "mark as read" path is `setActivePeer` → `markConversationViewed` (which `saveHistory`s synchronously when `updated==true`). UIKit's context-menu `cleanConversationUnreadMessageCount` is a Tim2Tox no-op today (`tim2tox_sdk_platform.dart:4209-4223`); context-menu variant should be marked expected-fail.
- The toxee-owned context menu row now exposes `conversation_context_menu_mark_read_item`; the anchor is usable for UI automation, but the underlying Tim2Tox context-menu action is still the documented no-op/expected-fail path.
- The toxee-owned conversation context menu now ships `UiKeys.conversationContextMenuMarkReadItem` as an anchor for that menu row, but the key only anchors discovery; it does not change the Tim2Tox no-op status above.
- `markConversationViewed` is `unawaited` in `setActivePeer`; in-memory `_unreadByPeer[id]=0` is sync, disk write follows ≤50ms — add 500ms buffer before SIGKILL for paranoia.
- BadgeService debounce 200ms + same-value coalesce — only one `badge written: 0` per debounce window even if multiple emits queued.
- Phone breakpoint (<720pt) hides sidebar; phone-S19 variant re-anchors A1+A5 on `bottomNavChatsUnreadBadge`.
- Locale pin matters until `sidebarChatsUnreadBadge` key lands; without it, label substring scraping breaks under S38-style locale rotation.
