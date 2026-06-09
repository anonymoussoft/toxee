# S158 — Conference: selecting the Conference segment updates the hint text

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once `AddGroupDialog` is runner-covered; adjacent sibling is S156
**Status**: covered at the widget layer — `test/ui/add_group_dialog_test.dart` selects the Conference segment and asserts the localized helper hint updates.
**Covered-by**: `test/ui/add_group_dialog_test.dart`
**Covered-by**: `test/ui/conference/conference_create_dialog_real_ui_test.dart`

## Precondition
- `AddGroupDialog` is open and the group-type selector is visible.

## UI Driver
1. Inspect the default hint text under `UiKeys.addGroupTypeSelector`.
2. Tap the Conference segment by label/ref.
3. Re-read the hint text.

## Assertions
- The helper copy switches to the localized `conferenceHint` string.
- The selector remains on the Conference segment after the hint updates.
- No runtime errors appear vs baseline.

## Notes
- This case is directly grounded in `AddGroupDialog._groupTypeHint`.
- It is the most conference-specific real-ui signal in the create dialog today.
