# S130 — Group: composer focus, type, and send

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once desktop Enter injection is packaged for group chats; adjacent siblings are S120 and S34
**Status**: covered — **live-validated 2026-06-08** by the `group_create` real-UI gate (`drive_real_ui_pair.dart` `runGroupCreate` → `sendComposerMessage`): the gate types + sends a unique message through the REAL group composer and asserts the own-sent bubble renders in the group history (`_waitGroupMessageAnyConversation`). The two-process delivery half is `group_message` (S151). Runner: `--real-ui-campaign=group-create` (`PASS: real-UI group create+open+composer-send`).

## Precondition
- Group `<gidG>` is open in the message pane.
- The desktop composer is rendered with `UiKeys.chatInputTextField`.

## UI Driver
1. Focus the composer field.
2. Type a unique text payload.
3. Submit via a real Return / Enter event.
4. Re-snapshot the message list.

## Assertions
- The just-sent text appears as a self message in the opened group chat.
- The send path uses the real composer, not `l3_send_group_text`.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of S120.
- On desktop, send is still keyboard-driven; a synthetic tap-only runner is insufficient.
