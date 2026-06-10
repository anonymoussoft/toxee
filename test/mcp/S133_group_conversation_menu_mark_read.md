# S133 — Group: mark-read from the conversation-row context menu

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] unread=present`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once a reproducible unread group fixture and row-menu runner exist; adjacent single-chat sibling is S118
**Status**: covered at the widget layer (L1) — the mark-read item's enabled/disabled state based on hasUnread for group rows is gated by `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart` (test "S133 NGC group mark-read item is enabled when hasUnread, disabled otherwise"). Also LIVE-VALIDATED 2026-06-08 by the real-UI gates — both the surface AND the true unread>0→0 transition.
**Covered-by**: `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart` (1) The single-instance `group_menu_mark_read` gate (campaign `group-menu`) creates a group, opens its row menu via `l3_open_conversation_menu`, and asserts the Mark-as-read item surfaces + unread stays 0 (a single instance cannot seed group unread). (2) The two-process follow-up is now DONE: the `group_menu_mark_read_unread` gate (campaign `group-menu-mark-read-unread`) has B send into the group while A is NOT viewing it (A's active conversation cleared via `l3_set_active_conversation`), so A accrues REAL group unread (`ffi_chat_service`: `_activePeerId != gid` → `_unreadByPeer[gid]++`), then A marks read via the row menu's `mark_read` action and the count drops to 0 through the production `cleanConversationUnreadMessageCount` → `markConversationRead` path. **Live: PASS (unread>0 → 0, gid=tox_1).** Sibling of S118 (identical menu dispatch). Shared desktop+mobile. See [[real_ui_group_message_fresh_nontest]].

## Precondition
- Group `<gidG>` has unread state while not being the active chat.
- The row is visible in the chats list.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidG>")`.
2. Tap the mark-read action.
3. Re-read the row and unread counters.

## Assertions
- The unread badge/count for `<gidG>` drops to zero.
- The row stays in place; only unread state changes.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of S118.
- The missing piece today is a stable real-ui runner for the row-menu tap, not the underlying unread model.
