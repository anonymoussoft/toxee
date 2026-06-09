# S176 — Conference: group-notifications tab shows a pending conference invite row

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A inviter,B invitee in separate sandboxes) current(B)=B1 autoLogin=on network=online friends=1 pendingConferenceInvite=present`
**Harness mode**: peerHarness=none (two toxee processes; pending invite required)
**Promotion target**: L3 candidate once real-ui group-notifications runners exist; adjacent siblings are S146 and S110
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_notifications_real_ui_test.dart`). PRODUCTION REALITY: toxee INTENTIONALLY omits the "Group notifications" Contacts tab, and `acceptGroupApplication`/`refuseGroupApplication` are no-ops (`tim2tox_sdk_platform.dart`); a conference invite is delivered + accepted over the NATIVE onGroupInvited / auto-join path (B auto-joins via `tox_conference_join`), never surfaced as a pending row — the conference analog of the S110 finding. The L1 gate drives the shared fork invite-row widget (`TencentCloudChatContactGroupApplicationItemButton`) directly, asserting it renders the keyed accept/refuse affordances for a conference application. The native auto-join acceptance is the two-process `conference_message` gate.
**Covered-by**: `test/ui/conference/conference_notifications_real_ui_test.dart`

## Precondition
- A conference `V2TimGroupApplication` (pending) is constructed for `<gidC>`.

## UI Driver
1. Pump the shared fork invite-row widget for the conference application.
2. Inspect the keyed accept affordance and the action buttons.

## Assertions
- The invite row exposes the keyed `group_invite_accept_button:<gidC>` accept affordance.
- Both the Accept and Decline action buttons render while the invite is pending.
- No runtime errors appear vs baseline.

## Notes
- toxee does NOT wire this widget into the Contacts page (the group-notifications tab is omitted); this gate covers the shared fork surface, while the real conference-invite acceptance is the native auto-join (S181/S184 two-process).
- This is the conference analog of S146 / S110.
