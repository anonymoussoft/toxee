# S178 — Conference: clear-history row opens the confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once the profile destructive-row tap is runner-covered; adjacent sibling is S148
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the keyed clear-history row and asserts the confirm dialog mounts for the conference/profile branch too.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference profile is open for `<gidC>`.
- The upper destructive row `UiKeys.groupProfileClearHistoryButton` is visible.

## UI Driver
1. Tap `UiKeys.groupProfileClearHistoryButton`.
2. Wait for the confirm dialog to mount.

## Assertions
- The clear-history confirm dialog opens from the real keyed row.
- The dialog exposes cancel/confirm actions without crashing the route.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S148.
- The dialog flow is shared with groups; the product difference is in conference semantics, not the surface.
