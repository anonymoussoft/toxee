# S181 — Conference: realtime message delivery through the real UI

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e groups=[gidC joined by both] accounts=2(A,B) autoLogin=on network=online`
**Harness mode**: peerHarness=none (two toxee processes; echo peer is not a substitute)
**Promotion target**: L3-pinned candidate once `2proc-ui` grows a conference-message branch; adjacent siblings are S151 and S34
**Status**: covered — **live-validated 2026-06-08** by the `conference_message` real-UI gate (`drive_real_ui_pair.dart`, the conference analogue of S151's `group_message`): with an existing friendship, A creates a conference, invites B (`tox_conference_invite`), B auto-joins (`tox_conference_join`), peers connect (members=2 both sides), then both deliver bidirectionally through the real composer (`PASS: bidirectional real-UI CONF message delivery`). Runner: `--real-ui-campaign=accepted-friend-inline-conference-message`.
**Covered-by**: `test/ui/conference/conference_composer_real_ui_test.dart`

## Precondition
- A and B are both Online and already joined to `<gidC>`.
- Both can open the same conference conversation through the real chats UI.

## UI Driver
1. On A, open `<gidC>` and send a unique text through the real composer.
2. On B, poll the real UI for the inbound text.
3. Optionally reverse the direction once.

## Assertions
- The inbound text appears on B without using `l3_send_group_text`.
- The receive path proves the real UI sits on top of the live two-process conference transport.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the conference analog of S151.
- Conference transport is the legacy branch, so this case is valuable even though the UI surface looks group-like.
