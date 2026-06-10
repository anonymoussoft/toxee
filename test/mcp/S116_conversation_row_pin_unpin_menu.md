# S116 — Conversation row: Pin / unpin via context-menu items (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=any friends=1 history=seeded`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L1 WidgetTester — the conversation right-click menu already opens in a real-UI gate (`test/ui/chat_core_real_ui_test.dart:368`, "conversation list item: right-click opens the real context menu"); pinning the keyed item is the L1-promotable step. L3 today because the marionette right-click / long-press menu-open gesture path is not yet a runnable gate.
**Status**: covered at the widget layer (L1) — the pin/unpin key flip (isPinned controls which key is exposed) is gated by `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart` (tests "S116 C2C conversation-row menu pin item key flips with pinned state" and "S116 C2C pin and unpin items both carry value:pin"). The data-half gate `l3_pin_toggle.json` remains the stable hard gate for the Prefs round-trip.
**Covered-by**: `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart`

> Real-MENU upgrade of S84. S84 drives `FakeConversationManager.setPinned` directly (hermetic data-half). S116 opens the row's REAL context menu and taps the keyed Pin / Unpin item, so the toggle flows through the actual UI path: menu item → `pinConversation` (home_page.dart:1601-1605).

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline) with a seeded C2C conversation (`conversationID = c2c_3116CBE0…7244`). Restore wipes existing state; cache miss auto-regenerates.
- Pinned set starts **empty**: `l3_dump_state.pinnedConversations == []` (read from `Prefs.getPinned()`, l3_debug_tools.dart:3563; the store key for C2C is the normalized bare id `3116CBE0974181B6`, `normalizeToxId`, tox_utils.dart:17). A dirty pinned set means a previous run leaked — re-restore.
- Account A logged in, plaintext, sidebar Online (poll `<nick>\nOnline` ≤60s); the post-frame context-menu handler has registered (no `[HomePage] Failed to register conversation context-menu handlers`, home_page.dart:376).
- F's conversation row present in the Chats tab as `UiKeys.conversationListTile("c2c_3116CBE0…7244")` (`conversation_list_item:c2c_3116CBE0…7244`, attached in the fork at tencent_cloud_chat_conversation_list.dart:118).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart   # includes tool/mcp_test/scenarios/l3_pin_toggle.json
```

`l3_pin_toggle.json` is the hermetic hard gate for the pin STATE (S84): `set_pinned true` → `wait_for pinnedConversations contains 3116CBE0974181B6` → `set_pinned false` → `pinnedConversations == []`. It drives `l3_set_pinned` → `FakeConversationManager.setPinned` (fake_managers.dart:285) directly, bypassing the menu. S116 below adds the REAL menu-item tap on top of that proven state path; there is no runnable gate for the marionette menu-open + item-tap itself (that is the L1 promotion target above).

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`. Confirm `l3_dump_state.pinnedConversations == []` and `conversations[]` for the peer reports `isPinned: false`.
2. Open the row's context menu on `UiKeys.conversationListTile("c2c_3116CBE0…7244")`:
   - **DESKTOP**: secondary (right) click — fires `onSecondaryTapConversationItem` → `_showConversationContextMenu` (home_page.dart:328-336, :1582 `showMenu`). The real-UI parallel is `chat_core_real_ui_test.dart:368`.
   - **MOBILE/marionette**: `marionette.long_press(UiKeys.conversationListTile(...))` (`ext.flutter.marionette.longPress`, verb confirmed per REAL_UI_GATES) → `onLongPressConversationItem` → same `_showConversationContextMenu` (home_page.dart:337-345).
3. Tap `UiKeys.conversationContextMenuPinItem` (`conversation_context_menu_pin_item`, home_page.dart:127, value `'pin'`) — only this key is present while unpinned (the item key is `isPinned ? Unpin : Pin`, home_page.dart:125-127).
4. Poll `l3_dump_state` ≤2s: `pinnedConversations` now contains `3116CBE0974181B6`; the peer's `conversations[].isPinned == true`.
5. Reopen the menu (Step 2 gesture). Now the keyed item is `UiKeys.conversationContextMenuUnpinItem` (`conversation_context_menu_unpin_item`, home_page.dart:126, value `'pin'`). Tap it.
6. Poll `l3_dump_state` ≤2s: `pinnedConversations == []`; the peer's `isPinned == false` (restored).

## Assertions
- A1 (clean baseline): Step 1 — `l3_dump_state.pinnedConversations == []` and the peer's `conversations[].isPinned == false`.
- A2 (pin via menu, primary): after Step 3 — `l3_dump_state.pinnedConversations` stringifies to include `3116CBE0974181B6` (the normalized bare key; the 16-char uppercase prefix matches a `contains` substring); AND the peer's `conversations[].isPinned == true` (UIKit list re-sort, `UikitDataFacade.conversationList`).
- A3 (menu reflects state): after Step 3, reopening the menu (Step 5) exposes `conversation_context_menu_unpin_item` and NO `conversation_context_menu_pin_item` (the key flips on `isPinned`, home_page.dart:125-127). This is the regression-canary that the menu reads live pin state.
- A4 (unpin via menu, restores): after Step 6 — `l3_dump_state.pinnedConversations == []` and `isPinned == false`; the fixture self-cleans.
- A5: `official.get_runtime_errors({})` matches the Step-1 baseline; `[HomePage] pinConversation failed for <convId>` (home_page.dart:1607) MUST NOT appear (logs only on failure).

## Notes
- L3-pin reason: the marionette menu-open gesture (desktop right-click / mobile long-press) is not yet a runnable gate; the pin STATE is gated hermetically by `l3_pin_toggle.json`, and the real menu-open is proven by WidgetTester `chat_core_real_ui_test.dart:368`. S116 is the bridge — assert the data-half state after the real item tap.
- Keys verified: `conversationContextMenuPinItem` @ home_page.dart:127, `conversationContextMenuUnpinItem` @ home_page.dart:126 (both defined ui_keys.dart:176-181); menu built by `buildConversationContextMenuItems` (home_page.dart:117) via `showMenu` (home_page.dart:1582). Pin/unpin share `value:'pin'` — disambiguated by the KEY, not the value.
- Sibling distinction: S84 = hermetic `setPinned` data-half; S116 = real menu-item tap of the SAME toggle; S117 = the menu SURFACE (enumerate items only, no toggle). Group pinning is S121-cluster (same menu path with a `group_` id).
- Desktop right-click vs mobile long-press: both gestures route to the IDENTICAL `_showConversationContextMenu` (home_page.dart:334/343), so this scenario covers mobile via the shared handler. The desktop popup is a Flutter `showMenu` `PopupMenu`; a global tearDown resets the fork's static desktop popup (`isShow`/`entry`) between WidgetTester runs (REAL_UI_GATES #4) — irrelevant to the live marionette path but cited for the L1 promotion.
- The mark-read item is `enabled: hasUnread` (home_page.dart:144); the pin item is always enabled, so pin toggling is unconditional here.
