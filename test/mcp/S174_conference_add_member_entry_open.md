# S174 — Conference: add-member entry opens the picker

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC host] friends=present`
**Harness mode**: peerHarness=none (single-instance real UI for the picker-open surface)
**Promotion target**: L1/L3 candidate once the profile-to-picker navigation is runner-covered; adjacent sibling is S144
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_members_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- Conference host account A can open the profile for `<gidC>`.
- The conference allows invite/add-member actions.

## UI Driver
1. Open the conference profile.
2. Tap `UiKeys.groupAddMemberButton`.
3. Wait for the add-member picker page to mount.

## Assertions
- The add-member picker opens from the real conference profile entry.
- The picker renders the selectable friend list and confirm affordance.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S144.
- The entry key is shared; the backend invite branch differs later.
