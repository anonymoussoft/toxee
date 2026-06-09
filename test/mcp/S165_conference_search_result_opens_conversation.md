# S165 — Conference: search result opens the target conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded(keyword)`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once search runners cover conference rows; adjacent sibling is S135
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_conversation_row_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- Conference `<gidC>` contains a unique seeded keyword in its history.
- The global search UI is reachable from the running shell.

## UI Driver
1. Open search and enter the seeded keyword.
2. Wait for the result row keyed as `UiKeys.searchResultMessage("group_<gidC>")`.
3. Tap the result row.

## Assertions
- The tapped result opens the target conference conversation.
- The opened conversation reveals the matching history context.
- No runtime errors appear vs baseline.

## Notes
- Search keys already accept `group_<gid>` IDs regardless of whether the underlying item is a group or conference.
- This is the conference analog of S135.
