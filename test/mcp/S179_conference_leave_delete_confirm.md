# S179 — Conference: leave / delete row opens the confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC host-or-member]`
**Harness mode**: peerHarness=none (single-instance real UI for the confirm-surface half)
**Promotion target**: L1/L3 candidate once the destructive-row tap is runner-covered; adjacent sibling is S150
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the keyed leave row and asserts the role-appropriate confirm dialog opens under the conference/profile branch.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference profile is open for `<gidC>`.
- `UiKeys.groupProfileLeaveButton` is visible.

## UI Driver
1. Tap `UiKeys.groupProfileLeaveButton`.
2. Wait for the confirm dialog to mount.

## Assertions
- The leave/delete confirm dialog opens from the real keyed row.
- The dialog title matches the role-specific branch in the current conference state.
- No runtime errors appear vs baseline.

## Notes
- Conferences share the same keyed leave/delete row as groups.
- This is the conference analog of S150.
