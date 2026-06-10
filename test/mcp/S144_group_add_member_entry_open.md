# S144 — Group: add-member entry opens the picker

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG owner] friends=present`
**Harness mode**: peerHarness=none (single-instance real UI for the picker-open surface)
**Promotion target**: L1/L3 candidate once the profile-to-picker navigation is runner-covered; adjacent sibling is S124
**Status**: covered at the widget layer (L1) — a real entry tap pushes the production `TencentCloudChatGroupAddMember` route for a regular NGC group (`GroupType.Work`, `tox_group_*`) and the picker mounts with its real selectable friend rows (`add_member_contact_item:<userID>`) and the keyed `group_member_invite_confirm_button`. Also live-validated 2026-06-08 by the `group_add_member_open` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-add-member-open`, single-instance no-friend): A creates a PRIVATE group via the real Add Group dialog, then the ungated `l3_open_group_add_member` deep-link opens the REAL add-member screen; that gate asserts it mounted by waiting for the keyed confirm button.
**Covered-by**: `test/ui/group/group_add_member_real_ui_test.dart` (S144 widget gate, regular NGC group)

## Precondition
- Group owner account A can open the group profile for `<gidG>`.
- The group allows invites/add-member actions.

## UI Driver
1. Open the group profile.
2. Tap `UiKeys.groupAddMemberButton`.
3. Wait for the add-member picker page to mount.

## Assertions
- The add-member picker opens from the real profile entry.
- The picker renders the selectable friend list and confirm affordance.
- No runtime errors appear vs baseline.

## Notes
- This isolates the entry-navigation half of S124.
- It stays single-instance because it does not yet require a real invite round-trip.
