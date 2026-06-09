# S155 — Group: accepting an invite eventually updates the member list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A owner,B invitee in separate sandboxes) autoLogin=on network=online friends=1 groups=A-hosts pendingInvite->accepted`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3-pinned candidate once invite accept and member-list refresh are chained in `2proc-ui`; adjacent siblings are S36, S81, and S124
**Status**: covered — **live-validated 2026-06-08** by the `group_member_list` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-member-list`, requires friends). A creates a PRIVATE group and invites B over the friend link; B auto-accepts; once peers connect, the gate asserts A's authoritative NGC member count (`l3_group_member_count`) is >=2 (self + B). The members-entry UI surface is exercised best-effort (the group-profile route's keyed widgets are not currently flutter_skill-reachable — see S136 — so it does not gate PASS; the count is authoritative). Shares `group_message`'s residual same-host NGC peer-discovery flakiness (3-attempt retry).

## Precondition
- A has invited B to `<gidG>`.
- B has accepted the invite through the real UI.

## UI Driver
1. On A, open `<gidG>`'s member list after B accepts.
2. Poll the member list until B appears.

## Assertions
- B eventually shows up in A's member list for `<gidG>`.
- The real UI reflects the same post-accept membership that the two-process data-half expects.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the member-list convergence half shared across S36/S81/S124.
- It is especially useful for catching post-accept propagation lag in the real UI.
