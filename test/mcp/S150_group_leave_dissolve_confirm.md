# S150 — Group: leave / dissolve row opens the confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG owner-or-member]`
**Harness mode**: peerHarness=none (single-instance real UI for the confirm-surface half)
**Promotion target**: L1/L3 candidate once the destructive-row tap is runner-covered; adjacent sibling is S123
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the keyed leave row and asserts the role-appropriate confirm dialog opens.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- Group profile is open for `<gidG>`.
- `UiKeys.groupProfileLeaveButton` is visible.

## UI Driver
1. Tap `UiKeys.groupProfileLeaveButton`.
2. Wait for the confirm dialog to mount.

## Assertions
- The leave/dissolve confirm dialog opens from the real keyed row.
- The dialog title matches the role-specific branch (quit-group tip vs dismiss-group tip).
- No runtime errors appear vs baseline.

## Notes
- This is the dialog-surface half of S123 separated from the post-confirm state transition.
- It is useful even before a fully automatable owner/member fixture pair exists.
