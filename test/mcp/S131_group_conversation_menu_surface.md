# S131 — Group: conversation-row context-menu surface

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once right-click/long-press on group rows is runner-covered; adjacent sibling is S117
**Status**: covered at the widget layer (L1) — NGC group row tap selecting currentConversation + menu item key enumeration (pin/mark-read/delete present; unpin absent when unpinned; unpin present and pin absent when pinned) are gated by `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart`. Also live-validated 2026-06-08 by the `group_conversation_menu` real-UI gate.
**Covered-by**: `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart`

## Precondition
- Group `<gidG>` is visible in the chats list.
- The desktop or mobile path supports row context menus for group conversations through the shared conversation-row handlers.

## UI Driver
1. Open the Chats tab.
2. Right-click or long-press `UiKeys.groupListTile("<gidG>")`.
3. Observe the surfaced menu items.

## Assertions
- The shared conversation-row menu mounts for the group row.
- The surface includes the same family of actions expected for a group conversation: pin/unpin, mark read, and delete.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of S117.
- The row key is toxee-owned; the menu surface itself is shared with the conversation list implementation.
