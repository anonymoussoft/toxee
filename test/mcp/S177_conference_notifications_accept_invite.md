# S177 — Conference: accept a pending conference invite from the group-notifications tab

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A inviter,B invitee in separate sandboxes) current(B)=B1 autoLogin=on network=online friends=1 pendingConferenceInvite=present`
**Harness mode**: peerHarness=none (two toxee processes; pending invite required)
**Promotion target**: L3 candidate once the accept-button flow is wired into a real-ui runner; adjacent siblings are S147 and S81
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_notifications_real_ui_test.dart`). The gate taps the keyed accept affordance and proves the REAL `onAcceptApplication → contactSDK.acceptGroupApplication` path runs end-to-end (an `onSDKFailed` probe fires for `acceptGroupApplication` on the hermetic not-init path, with no spurious success transition). PRODUCTION REALITY (see S176): toxee omits the group-notifications tab and conference invites auto-join natively; the actual join (B joins `<gidC>`, the conversation row appears) is the two-process `conference_message` gate.
**Covered-by**: `test/ui/conference/conference_notifications_real_ui_test.dart`

## Precondition
- The shared fork invite-row widget is mounted for a pending conference application `<gidC>`.

## UI Driver
1. Tap `UiKeys.groupInviteAcceptButton("<gidC>")`.
2. Observe the handler dispatch (onSDKFailed probe) and the row state.

## Assertions
- Tapping accept drives the real `acceptGroupApplication` handler (the `onSDKFailed` probe captures that exact API on the not-init path).
- The not-init failure branch keeps the action buttons (no spurious "accepted" transition).
- No runtime errors appear vs baseline.

## Notes
- The success transition + the native conference join are the wired / two-process leg (`conference_message`).
- The same row/button family is shared with non-conference invites.
