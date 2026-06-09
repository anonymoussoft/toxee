# S118 — Conversation row: Mark-read via context-menu item (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded(≥1 inbound unread)`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L1 WidgetTester for the real menu-open + item tap (`chat_core_real_ui_test.dart:368` proves the conversation menu opens; the mark-read item is keyed). The unread→0 ASSERTION is L3 only and currently **expected-fail via this menu path** — see Status.
**Status**: covered — LIVE-VALIDATED 2026-06-08 by the two-process real-UI gate (the prior "EXPECTED-FAIL / no-op" conclusion was STALE). The menu's `cleanConversationUnreadMessageCount` is NOT a no-op: it calls `ffiService.markConversationRead` (`tim2tox_sdk_platform.dart:4257-4284`) which advances the persisted read barrier (`markConversationViewed`), flags messages `isRead`, zeroes the in-memory unread counter, and fires `onConversationUnreadCleared` to refresh the list — so the context-menu Mark-as-read genuinely drives unread→0. The `group_menu_mark_read_unread` gate (`drive_real_ui_pair.dart`, campaign `group-menu-mark-read-unread`) establishes a two-process group, clears A's active conversation (`l3_set_active_conversation`), has B send so A accrues REAL unread (`ffi_chat_service`: `_activePeerId != gid` → `_unreadByPeer[gid]++`), asserts A's row `unreadCount>0`, marks read via the row menu's `mark_read` action (the SAME `_dispatchConversationMenuAction` the menu runs), and asserts `unreadCount→0`. **Live: PASS (unread>0 → 0, gid=tox_1).** The menu `mark_read` dispatch is identical for C2C and group rows, so this also covers the C2C conversation-row case. Shared desktop+mobile. See [[real_ui_group_message_fresh_nontest]].

> Real-MENU upgrade of S19, with a sharp honesty caveat. S19's working "mark as read" is `setActivePeer` → `markConversationViewed`. The toxee context-menu Mark-read item instead calls `cleanConversationUnreadMessageCount` (home_page.dart:1619-1625), which Tim2Tox implements as a no-op returning success (tim2tox_sdk_platform.dart:4269-4282). So the menu item is keyed and tappable, but on Tim2Tox it does NOT clear unread today.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` (idempotent; captures `peer_id` from `tool/mcp_test/echo_peer.json`; bot mirrors c2c text verbatim). Teardown `bash tool/mcp_test/stop_echo_peer.sh`. Peer must reach Online (poll, don't sleep) so an inbound mirror lands and increments unread.
- Seed an unread: send `mark-read-probe-<nonce>` to the peer; the echo mirrors it back as INBOUND (`isSelf:false`), so `l3_dump_state` for the peer reports `unreadCount >= 1` and `totalUnreadCount >= 1`. (`unreadCount` is read path-independently from `FfiChatService.getC2CUnreadCount`, l3_debug_tools.dart:3790, so the count is the same value the working `l3_mark_read` would zero.)
- Account A logged in, plaintext, sidebar Online (poll ≤60s); context-menu handler registered (no `[HomePage] Failed to register conversation context-menu handlers`, home_page.dart:376).
- F's row present as `UiKeys.conversationListTile("c2c_<toxF>")` (`conversation_list_item:c2c_<toxF>`, fork tencent_cloud_chat_conversation_list.dart:118). With `hasUnread == true`, the mark-read item renders **enabled** (home_page.dart:144).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart   # includes tool/mcp_test/scenarios/l3_unread_mark_read.json (nonBlocking)
```

`l3_unread_mark_read.json` is the data-half for the WORKING mark-read path: warmup → `send_text` → `wait_for message_exists isSelf:false` → `wait_for unread_at_least 1` → `mark_read` (the `l3_mark_read` tool drives `setActivePeer`/`markConversationViewed`, NOT the menu's no-op) → assert `unreadCount == 0`. It is `nonBlocking` (the live echo + DHT timing makes `unread > 0` race-prone; one pass is not proof). S118's marionette MENU tap below exercises the keyed UI item, which routes to the no-op `cleanConversationUnreadMessageCount` — so the UI tap does NOT reproduce the runner's unread→0; assert that reality (A3/A4).

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`. Capture the seeded `unreadCount` (≥1) and `totalUnreadCount` for the peer from `l3_dump_state`.
2. Open the row's menu on `UiKeys.conversationListTile("c2c_<toxF>")`:
   - **DESKTOP**: right-click → `onSecondaryTapConversationItem` → `_showConversationContextMenu` (home_page.dart:328-336, :1582).
   - **MOBILE/marionette**: `marionette.long_press(...)` (`ext.flutter.marionette.longPress`) → `onLongPressConversationItem` → same handler (home_page.dart:337-345).
3. Tap `UiKeys.conversationContextMenuMarkReadItem` (`conversation_context_menu_mark_read_item`, home_page.dart:142, value `'mark_read'`). This invokes `cleanConversationUnreadMessageCount` (home_page.dart:1619-1625).
4. Poll `l3_dump_state` ≤2s and re-read the peer's `unreadCount` / `totalUnreadCount`.

## Assertions
- A1 (seeded unread, control): Step 1 — the peer's `conversations[].unreadCount >= 1` and `totalUnreadCount >= 1` (proves the gate is non-vacuous; without it A3 is meaningless).
- A2 (item enabled): the mark-read item renders enabled (`hasUnread == true`, home_page.dart:144); it is tappable, not greyed.
- A3 (**EXPECTED-FAIL today — the no-op reality**): after tapping the menu item, the peer's `unreadCount` is UNCHANGED (still ≥1) — `cleanConversationUnreadMessageCount` returned success without zeroing (tim2tox_sdk_platform.dart:4274-4281). Mark this assertion `expected-fail`; it is the regression-canary that documents the no-op. Flip it to "unread→0" ONLY if/when the platform implements the clear.
- A4 (no error path): `[HomePage] cleanConversationUnreadMessageCount failed for <convId>` (home_page.dart:1628) MUST NOT appear (the no-op returns code 0; failure would be a different bug).
- A5 (the WORKING path, cross-ref): the unread→0 that DOES work is `l3_unread_mark_read.json` via `setActivePeer`/`markConversationViewed` — drive it (or open the conversation in the UI, S19) and assert `unreadCount == 0`. This is the real mark-read coverage; S118's menu tap is the surface, not the side-effect.
- A6: `official.get_runtime_errors({})` matches the Step-1 baseline.

## Notes
- L3-pin + expected-fail reason: the toxee context-menu Mark-read calls `cleanConversationUnreadMessageCount`, a Tim2Tox no-op (tim2tox_sdk_platform.dart:4269-4282 — "just returns success … handled … through other mechanisms"). The working clear is `setActivePeer`/`markConversationViewed` (S19 notes). S118 documents the no-op honestly; it must NOT claim a passing unread→0 via the menu.
- Keys verified: `conversationContextMenuMarkReadItem` @ home_page.dart:142 (defined ui_keys.dart:185-186); the call site is home_page.dart:1614-1625. The item is `enabled: hasUnread` (home_page.dart:144).
- Carry S19's caveat: `l3_unread_mark_read.json` is `nonBlocking`/FLAKY (live echo + DHT timing; per-run `{{nonce}}` so stragglers can't be miscounted). The unread/DHT race means one pass is not proof of the WORKING path either.
- Sibling distinction: S19 = the working mark-read via open-conversation (`setActivePeer`); S118 = the real menu-item tap, which hits the no-op. S116 = pin item (works), S117 = menu surface, S119 = delete item.
- Desktop right-click vs mobile long-press: both route to the SAME `_showConversationContextMenu` (home_page.dart:334/343) → the no-op affects mobile identically (shared Dart path). No mobile-specific divergence.
