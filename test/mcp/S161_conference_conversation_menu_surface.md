# S161 — Conference: conversation-row context-menu surface

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once right-click/long-press on conference rows is runner-covered; adjacent sibling is S131
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_conversation_row_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is visible in the chats list.

## UI Driver
1. Open the Chats tab.
2. Right-click or long-press `UiKeys.groupListTile("<gidC>")`.
3. Observe the surfaced menu items.

## Assertions
- The shared conversation-row menu mounts for the conference row.
- The menu surface matches the expected conversation-level actions for a conference.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S131.
- The row/menu layer is shared with groups and C2C; conference behavior differs mostly in downstream data semantics.
