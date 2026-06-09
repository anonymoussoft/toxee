# S157 — Conference: copy the created conference ID from Add Group dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once the post-create success state remains visible long enough to tap copy; adjacent sibling is S156
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_create_dialog_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_create_dialog_real_ui_test.dart`

## Precondition
- A conference create flow has just completed in `AddGroupDialog`.
- The created-ID affordance remains visible long enough to tap `UiKeys.addGroupCopyIdButton`.

## UI Driver
1. Create a conference from `AddGroupDialog`.
2. Tap `UiKeys.addGroupCopyIdButton`.
3. Read the clipboard and compare it to the created conference row.

## Assertions
- The clipboard receives a 64-hex conference ID.
- The copied ID corresponds to the newly created conference row.
- No runtime errors appear vs baseline.

## Notes
- This mirrors S128 on the conference branch.
- The current auto-pop timing is still the main blocker for a stable runner.
