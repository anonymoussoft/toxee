# S148 — Group: clear-history row opens the confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once the profile destructive-row tap is runner-covered; adjacent sibling is S122
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the keyed clear-history row and asserts the confirm dialog mounts with cancel/confirm actions.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- Group profile is open for `<gidG>`.
- The upper destructive row `UiKeys.groupProfileClearHistoryButton` is visible.

## UI Driver
1. Tap `UiKeys.groupProfileClearHistoryButton`.
2. Wait for the confirm dialog to mount.

## Assertions
- The clear-history confirm dialog opens from the real keyed row.
- The dialog exposes cancel/confirm actions without crashing the route.
- No runtime errors appear vs baseline.

## Notes
- This narrows S122 to the dialog-surface half.
- It is useful even before a dedicated `l3_clear_group_history` tool exists.
