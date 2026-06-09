# S164 — Conference: delete from the conversation-row context menu and confirm

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once real row-menu delete taps are runner-covered; adjacent siblings are S134 and S119
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_conversation_row_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is visible in the chats list with non-empty history.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidC>")`.
2. Tap the delete action.
3. Confirm through the surfaced confirm dialog.
4. Re-read the row and conversation state.

## Assertions
- The delete/confirm surface mounts from the real conference row menu.
- The conference row reflects the post-delete behavior expected by the shared conversation manager path.
- No runtime errors appear vs baseline.

## Notes
- This mirrors S134's group counterpart but keeps the row title / conversation under the conference branch.
- Exact row persistence/removal semantics remain a runner-time observable.
