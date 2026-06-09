# S129 — Group: open a conversation from the chat list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L2/L3 candidate once a hermetic real-ui conversation-open runner exists; adjacent siblings are S11 and S34
**Status**: covered — **live-validated 2026-06-08** by the `group_create` real-UI gate (`drive_real_ui_pair.dart` `runGroupCreate` → `openGroupChat`): after creating a group, the gate opens its conversation through the real chats UI and asserts the group chat surface is ready (`_chatSurfaceReadyForAnyGroup` with the exact `group_<id>` match). Also exercised on both sides by `group_message`. Runner: `--real-ui-campaign=group-create`.

## Precondition
- One signed-in account A is Online.
- Group `<gidG>` already has at least one seeded message so its row is visible.

## UI Driver
1. Open the Chats tab.
2. Tap `UiKeys.groupListTile("<gidG>")`.
3. Wait for the group message panel to mount.

## Assertions
- The active chat header reflects the target group.
- The composer subtree mounts for the opened group chat.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of S11 using toxee's owned `group_list_tile:<gid>` anchor.
- The group row key lives at the toxee override boundary, not upstream UIKit.
