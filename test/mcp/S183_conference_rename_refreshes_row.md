# S183 — Conference: profile rename refreshes the conversation row title

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC host] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once rename + row-refresh are runner-covered together; adjacent sibling is S153
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_profile_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- A hosts `<gidC>` and can rename it from the profile dialog.

## UI Driver
1. Rename `<gidC>` through the profile edit dialog.
2. Return to the chats list.
3. Inspect `UiKeys.groupListTile("<gidC>")`.

## Assertions
- The conversation row title refreshes to the renamed conference value.
- The rename propagates through the real UI path rather than a direct prefs edit.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S153.
- It is a useful parity check against the conversation-list display-name resolution for `groupType='conference'`.
