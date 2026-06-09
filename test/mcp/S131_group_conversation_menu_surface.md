# S131 — Group: conversation-row context-menu surface

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once right-click/long-press on group rows is runner-covered; adjacent sibling is S117
**Status**: covered — **live-validated 2026-06-08** by the `group_conversation_menu` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-menu-surface`): A creates a group, opens its conversation-row context menu via the ungated `l3_open_conversation_menu` deep-link (flutter_skill cannot right-click / long-press), and asserts the Pin + Mark-as-read + Delete item keys surface. Single-instance (no friendship).

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
