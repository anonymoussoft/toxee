# S152 — Group: alternating burst send through the real UI

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e groups=[gidG joined by both] accounts=2(A,B) autoLogin=on network=online history=empty`
**Harness mode**: peerHarness=none (two toxee processes; live group transport required)
**Promotion target**: L3-pinned candidate once `2proc-ui` grows a reusable group-burst campaign; adjacent siblings are S64 and S34
**Status**: covered — **live-validated 2026-06-08** by the `group_burst` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-burst`, requires friends). Establishes a live two-process PRIVATE group (A creates, B auto-joins over the friend link, peers connect) then alternates 3 messages each way through the REAL group composer; PASS requires all 6 sends to render in-group on the receiver (`_waitGroupMessageAnyConversation`). Shares `group_message`'s residual same-host cross-process NGC peer-discovery flakiness (3-attempt fresh-group retry).

## Precondition
- A and B share joined group `<gidG>`.
- Both sides can focus the real group composer.

## UI Driver
1. Alternate A->group and B->group sends for a short burst.
2. Poll both real UIs until the tail messages land.

## Assertions
- The full burst lands on both sides in the expected order/window.
- The real UI remains stable under repeated focus/type/send cycles.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the group analog of S64's real-ui ambition.
- The missing ingredient is a reusable `2proc-ui` scenario/campaign, not a new L3 JSON gate.
