# S145 — Group: add-member picker selects a friend and confirms

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A owner,B friend in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online groups=[gidG owner] friends=1`
**Harness mode**: peerHarness=none (two toxee processes; invite target required)
**Promotion target**: L3 candidate once picker-row targeting is keyed; adjacent sibling is S124
**Status**: covered at the widget layer (L1) — the real picker for a regular NGC group (`GroupType.Work`) is driven end to end: tap the keyed friend row `add_member_contact_item:<userID>`, tap `group_member_invite_confirm_button`, and the production `submitAdd` → `contactPresenter.inviteUserToGroup` → platform `inviteUserToGroup` is captured (call count == 1, selected friend in the user list) via a custom-platform seam. Also live-validated 2026-06-08 by the `group_add_member_picker` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-add-member-picker`, runs `handshake` first): two-process friended pair where A invites B by the keyed row and B (autoAcceptGroupInvites on) joins over the friend link — asserted by A's NGC member count reaching 2 (shares the same-host cross-process NGC discovery limitation of the other two-process group gates).
**Covered-by**: `test/ui/group/group_add_member_real_ui_test.dart` (S145 widget gate, captured invite call)

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
- The per-row key gap is RESOLVED: the picker rows are keyed `add_member_contact_item:<userID>` and the confirm is `group_member_invite_confirm_button` (`tencent_cloud_chat_group_add_member.dart:351,90`). Selection no longer relies on text/semantic targeting.
- This is the picker-confirm half of S124 separated from the full two-process narrative.
