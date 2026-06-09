# S145 — Group: add-member picker selects a friend and confirms

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A owner,B friend in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online groups=[gidG owner] friends=1`
**Harness mode**: peerHarness=none (two toxee processes; invite target required)
**Promotion target**: L3 candidate once picker-row targeting is keyed; adjacent sibling is S124
**Status**: covered — **live-validated 2026-06-08** by the `group_add_member_picker` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-add-member-picker`, runs `handshake` first). Two-process friended pair: A creates a PRIVATE group, opens the REAL add-member picker via `l3_open_group_add_member`, selects B by the keyed `add_member_contact_item:<B-userId>` (resolved from A's friends by pubkey), taps `group_member_invite_confirm_button` (inviteUserToGroup); B (autoAcceptGroupInvites on) joins over the friend link — asserted by A's NGC member count reaching 2. Shares the same-host cross-process NGC discovery limitation of the other two-process group gates.

## Precondition
- A and B are already mutual friends.
- A has the add-member picker open for `<gidG>`.

## UI Driver
1. Select B in the picker.
2. Tap `UiKeys.groupMemberInviteConfirmButton`.
3. Observe the immediate UI response on A.

## Assertions
- The confirm action dispatches the real invite-to-group path.
- A remains on the expected surface without runtime errors.
- No runtime errors appear vs baseline on either side.

## Notes
- The current blocker is the missing per-row key inside the picker; selection still relies on text/semantic targeting.
- This is the picker-confirm half of S124 separated from the full two-process narrative.
