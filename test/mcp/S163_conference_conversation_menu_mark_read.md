# S163 — Conference: mark-read from the conversation-row context menu

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] unread=present`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once a reproducible unread conference fixture and row-menu runner exist; adjacent siblings are S133 and S118
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_conversation_row_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- Conference `<gidC>` has unread state while not being the active chat.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidC>")`.
2. Tap the mark-read action.
3. Re-read the row and unread counters.

## Assertions
- The unread badge/count for `<gidC>` drops to zero.
- The conference row stays in place; only unread state changes.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S133.
- It deliberately targets the row-menu action rather than opening the chat to clear unread.
