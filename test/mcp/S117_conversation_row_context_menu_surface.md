# S117 — Conversation row: context-menu SURFACE (enumerate items)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=any friends=1 history=seeded(1 inbound unread)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L1 WidgetTester — `chat_core_real_ui_test.dart:368` already proves the REAL conversation context menu opens on right-click (`find.text('Delete')`); enumerating the keyed items is the L1-promotable surface gate.
**Status**: covered (surface gate only — item side effects are S116 pin / S118 mark-read / S119 delete). NOT "covered (executable)": the marionette menu-open + item-enumeration is a UI step, not a runnable gate.

S117 = the conversation-row analog of S15 (which gates the MESSAGE context-menu surface). Surface gate only: assert the expected keyed items are present and the menu dismisses with zero side effects. Tap-item behavior belongs to S116/S118/S119.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline), seeded C2C conversation `c2c_3116CBE0…7244` with **≥1 inbound unread** message (so `hasUnread == true` and the mark-read item renders enabled). Restore wipes existing state; cache miss auto-regenerates.
- Pinned set starts **empty** (`l3_dump_state.pinnedConversations == []`) so the unpinned-state menu variant is the default (Pin item, not Unpin).
- Account A logged in, plaintext, sidebar Online (poll ≤60s); context-menu handler registered (no `[HomePage] Failed to register conversation context-menu handlers`, home_page.dart:376).
- F's row present as `UiKeys.conversationListTile("c2c_3116CBE0…7244")` (`conversation_list_item:c2c_3116CBE0…7244`, fork tencent_cloud_chat_conversation_list.dart:118).

Variants (driven by row state at menu-open):
- **117a -unpinned-unread** (default): Pin + MarkRead(enabled) + Delete keyed items present; Unpin absent.
- **117b -pinned-read**: re-pin first (`l3_set_pinned true`) and clear unread (`l3_mark_read` / open then leave); reopen menu — Unpin present, Pin absent, MarkRead present-but-`enabled:false` (home_page.dart:144), Delete present.

## Executable Driver

No data-half runner gate enumerates this menu — the observable is "the keyed items exist", not a Prefs/history mutation. The REAL menu-open is proven at L1 by `chat_core_real_ui_test.dart:368` (right-click → `find.text('Delete')` on the conversation context menu). The marionette enumeration below IS the test at L3; promote to L1 by asserting `find.byKey(...)` on the four item keys.

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`. Confirm the peer's `conversations[].isPinned == false` and `unreadCount >= 1` (117a).
2. Open the menu on `UiKeys.conversationListTile("c2c_3116CBE0…7244")`:
   - **DESKTOP**: right-click → `onSecondaryTapConversationItem` → `_showConversationContextMenu` (home_page.dart:328-336, :1582).
   - **MOBILE/marionette**: `marionette.long_press(...)` (`ext.flutter.marionette.longPress`) → `onLongPressConversationItem` → same handler (home_page.dart:337-345).
3. Snapshot ≤500ms → enumerate the menu items by key (and by label as a fallback).
4. Dismiss WITHOUT selecting: tap outside the popup region (a `showMenu` route dismisses on barrier tap, returning `selected == null`, home_page.dart:1597 short-circuits). Re-snapshot.

## Assertions
- A1 (presence, 117a -unpinned-unread): the snapshot after Step 2 contains the expected keyed items:
  - `conversation_context_menu_pin_item` (home_page.dart:127, label `pinConversation`)
  - `conversation_context_menu_mark_read_item` (home_page.dart:142, label `markConversationAsRead`, **enabled** since `hasUnread`, home_page.dart:144)
  - `conversation_context_menu_delete_item` (home_page.dart:159, label `delete`)
- A2 (absence, 117a): `conversation_context_menu_unpin_item` is ABSENT (the pin/unpin item key is `isPinned ? Unpin : Pin`, home_page.dart:125-127; unpinned → Pin only). Pin XOR Unpin is exactly one item.
- A3 (117b -pinned-read): `conversation_context_menu_unpin_item` PRESENT, `conversation_context_menu_pin_item` ABSENT; `conversation_context_menu_mark_read_item` present but disabled (`enabled: hasUnread == false`, home_page.dart:144 — appears greyed via `scheme.onSurfaceVariant`, home_page.dart:150); `conversation_context_menu_delete_item` present.
- A4 (dismiss → no side effects): after Step 4 the snapshot contains none of the four item keys (menu gone); AND `l3_dump_state` is unchanged vs Step 1 — `pinnedConversations` same, peer `unreadCount` same, `conversationIds` same (a SURFACE gate must mutate nothing).
- A5: `official.get_runtime_errors({})` matches the Step-1 baseline.
- Negative grep (whole run): `[HomePage] pinConversation failed`, `[HomePage] cleanConversationUnreadMessageCount failed`, `[HomePage] deleteConversation failed`, `[FakeConversationManager] deleteConversation: START` MUST NOT appear (no item was activated).

## Notes
- L3-pin reason: marionette menu-open is not yet a runnable gate; the real menu-open is L1-proven (`chat_core_real_ui_test.dart:368`). S117 enumerates the keyed items; promote by `find.byKey` on the four keys.
- Keys verified: pin @ home_page.dart:127, unpin @ :126, markRead @ :142, delete @ :159 (defined ui_keys.dart:176-186); built by `buildConversationContextMenuItems` (home_page.dart:117). There is a `PopupMenuDivider` between markRead and delete (home_page.dart:157) — unkeyed, ignore it.
- Sibling distinction: S15 = MESSAGE-menu surface (UIKit overlay); S117 = CONVERSATION-row menu surface (toxee-owned `showMenu`). S116/S118/S119 own the per-item TAP side effects; S117 must leave zero side effects (A4).
- Desktop right-click vs mobile long-press: both route to the SAME `_showConversationContextMenu` (home_page.dart:334/343) → covers mobile via the shared handler. On desktop the popup is a Flutter `showMenu` route; `fmt_press_key({key:"Escape"})` is unreliable for dismissal — use a barrier/outside tap (the route pops on barrier tap). For the L1 WidgetTester promotion, the global tearDown resets the fork's static desktop popup state (REAL_UI_GATES #4) so a later test's right-click isn't suppressed.
- Items are tappable `PopupMenuItem`s; the only shown-but-disabled state is mark-read when `!hasUnread` (home_page.dart:144) — so "enabled/disabled" is observable here (distinct from S15, where all message-menu items are uniformly enabled).
