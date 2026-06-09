# S160 — Conference: composer focus, type, and send

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once desktop Enter injection is packaged for conference chats; adjacent siblings are S130 and S34
**Status**: covered — **live-validated 2026-06-08** by the `conference_message` real-UI gate: both sides type + send through the REAL conference composer and the peer receives it (`CONF A->B` and `CONF B->A` both `sent=recv=true`). Runner: `--real-ui-campaign=accepted-friend-inline-conference-message`.
**Covered-by**: `test/ui/conference/conference_composer_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is open in the message pane.
- The desktop composer is rendered with `UiKeys.chatInputTextField`.

## UI Driver
1. Focus the composer field.
2. Type a unique text payload.
3. Submit via a real Return / Enter event.
4. Re-snapshot the message list.

## Assertions
- The just-sent text appears as a self message in the opened conference chat.
- The send path uses the real composer rather than `l3_send_group_text`.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S130.
- The transport branch is still “group-like” at the UI layer even though the backend invite/join semantics differ.
