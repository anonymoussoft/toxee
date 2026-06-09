# S180 — Conference: leaving or deleting the conference removes the row

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC host-or-member] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once confirm-and-observe conference leave flows are runner-covered; adjacent siblings are S123 and S179
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_profile_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is visible in the chats list and openable in the profile.

## UI Driver
1. Open the conference profile.
2. Trigger leave/delete from `UiKeys.groupProfileLeaveButton` and confirm.
3. Return to the chats list.

## Assertions
- The conference row for `<gidC>` disappears from the chats list after a successful leave/delete flow.
- The post-confirm UI matches the same cleanup expectations discussed in S123, but for the conference branch.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of the state-change half of S123.
- Host/member semantics may still differ, but the row-removal expectation is the shared observable.
