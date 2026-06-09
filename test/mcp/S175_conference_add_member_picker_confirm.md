# S175 — Conference: add-member picker selects a friend and confirms

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A host,B friend in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online groups=[gidC host] friends=1`
**Harness mode**: peerHarness=none (two toxee processes; invite target required)
**Promotion target**: L3 candidate once picker-row targeting is keyed; adjacent siblings are S145 and S124
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_members_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- A and B are already mutual friends.
- A has the add-member picker open for `<gidC>`.

## UI Driver
1. Select B in the picker.
2. Tap `UiKeys.groupMemberInviteConfirmButton`.
3. Observe the immediate UI response on A.

## Assertions
- The confirm action dispatches the real conference invite path.
- A remains on the expected surface without runtime errors.
- No runtime errors appear vs baseline on either side.

## Notes
- The current blocker is still the missing per-row key inside the picker.
- The conference-specific transport branch is asserted more explicitly in S184.
