# S162 — Conference: pin / unpin from the conversation-row context menu

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once real row-menu tapping is runner-covered; adjacent siblings are S132 and `l3_pin_group_toggle`
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_conversation_row_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is visible in the chats list and starts unpinned.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidC>")`.
2. Tap the pin action.
3. Re-open the row menu and tap unpin.

## Assertions
- The conference row moves into and back out of the pinned ordering slot.
- The action modifies the same pinned-state substrate used by group/conference conversation rows.
- No runtime errors appear vs baseline.

## Notes
- Conference rows still reuse the shared pinning model.
- This is the conference analog of S132.
