# S147 — Group: accept a pending invite from the group-notifications tab

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A inviter,B invitee in separate sandboxes) current(B)=B1 autoLogin=on network=online friends=1 pendingGroupInvite=present`
**Harness mode**: peerHarness=none (two toxee processes; pending invite required)
**Promotion target**: L3 candidate once the accept-button flow is wired into a real-ui runner; adjacent siblings are S81 and S124
**Status**: N/A for toxee (2026-06-08, codex-reviewed) — intentional product scope. There is no group-application accept flow: `acceptGroupApplication()` is a Tim2Tox no-op (`tim2tox_sdk_platform.dart`) and the "Group notifications" Contacts tab is intentionally omitted. Group invites are AUTO-accepted natively (`tox_group_invite_accept` / `tox_conference_join`) over the friend link — which is exactly what the two-process `group_message`/`conference_message`/`group_add_member_picker` gates exercise. There is no manual-accept-via-notifications path to drive. See [[real_ui_group_message_fresh_nontest]].

## Precondition
- B has a visible pending group invite row for `<gidG>`.

## UI Driver
1. Open Contacts -> Group Notifications.
2. Tap `UiKeys.groupInviteAcceptButton("<gidG>")`.
3. Wait for the invite row to resolve and the chats list to refresh.

## Assertions
- Accepting the row joins B into `<gidG>`.
- A group conversation row for `<gidG>` appears in B's chats list.
- No runtime errors appear vs baseline.

## Notes
- This isolates the accept-button leg from the broader invite scenarios.
- The same accept-button family should work for future conference invite rows as well.
