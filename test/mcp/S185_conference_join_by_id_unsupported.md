# S185 — Conference: join-by-ID remains unsupported in the NGC join flow

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A host,B joiner in separate sandboxes) autoLogin=on network=online groups=[gidC host only]`
**Harness mode**: peerHarness=none (two toxee processes; negative real-ui/data-path case)
**Promotion target**: L3 candidate once the join dialog is runner-covered end-to-end; adjacent sibling is S33
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_create_dialog_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_create_dialog_real_ui_test.dart`

## Precondition
- A already hosts conference `<gidC>`.
- B is Online and not yet a member of `<gidC>`.

## UI Driver
1. On B, open `AddGroupDialog`.
2. Paste `<gidC>` into `UiKeys.addGroupJoinIdInput`.
3. Optionally fill request message / alias.
4. Tap the join CTA and observe the outcome.

## Assertions
- The client accepts the 64-hex input shape at the form layer.
- The downstream join path does not successfully join the conference through the current join-by-ID implementation.
- No ghost conference row is created on B after the failed join attempt.

## Notes
- This captures the boundary already called out in S33: conference IDs may be 64-hex, but the current join-by-ID flow is NGC-specific and does not cover legacy conferences.
- It is intentionally a negative scenario, not a parity case with group join.
