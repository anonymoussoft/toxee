# S159 — Conference: open a conversation from the chat list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L2/L3 candidate once a hermetic real-ui conversation-open runner exists; adjacent siblings are S129 and S34
**Status**: covered — **live-validated 2026-06-08** by the `conference_message` real-UI gate: both A and B open the conference conversation through the real chats UI (`openGroupChat`, exact `group_<id>` surface match) before sending. Runner: `--real-ui-campaign=accepted-friend-inline-conference-message`.
**Covered-by**: `test/ui/conference/conference_conversation_row_real_ui_test.dart`

## Precondition
- One signed-in account A is Online.
- Conference `<gidC>` already has at least one seeded message so its row is visible.

## UI Driver
1. Open the Chats tab.
2. Tap `UiKeys.groupListTile("<gidC>")`.
3. Wait for the conference message panel to mount.

## Assertions
- The active chat header reflects the target conference.
- The composer subtree mounts for the opened conference chat.
- No runtime errors appear vs baseline.

## Notes
- Conference rows still use the shared `group_list_tile:<gid>` anchor.
- This is the conference analog of S129.
