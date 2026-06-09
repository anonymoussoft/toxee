# S184 — Conference: invite flow uses the `tox_conference_invite` branch

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A host,B friend in separate sandboxes) autoLogin=on network=online friends=1 groups=[gidC host]`
**Harness mode**: peerHarness=none (two toxee processes; invite target required)
**Promotion target**: L3-pinned candidate once a `2proc-ui` conference-invite branch is codified; adjacent siblings are S175 and S81
**Status**: covered — **live-validated 2026-06-08** by the `conference_message` real-UI gate: A invites B to the conference through the REAL add-member screen (`inviteUserToGroup`), and the C++ `InviteUserToGroup` correctly takes the CONFERENCE branch (`tox_conference_invite`, not `tox_group_invite_friend`) — proven because B joins via `tox_conference_join` and bidirectional delivery succeeds. Runner: `--real-ui-campaign=accepted-friend-inline-conference-message`.
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- A hosts conference `<gidC>` and B is already a mutual friend.
- A can reach the add-member picker from the conference profile.

## UI Driver
1. Open the add-member picker for `<gidC>`.
2. Select B and confirm the invite.
3. Inspect A/B logs and the invite surface.

## Assertions
- The invite path logs the conference-specific native branch (`tox_conference_invite`) rather than the NGC group-invite branch.
- B receives a pending invite row or auto-join behavior consistent with conference invite handling.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the conference-specific version of the invite-branch distinction already documented inside S81/S124.
- The UI entry keys are shared; the important difference is the native invite branch and resulting delivery semantics.
