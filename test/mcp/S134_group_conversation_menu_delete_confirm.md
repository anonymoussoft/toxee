# S134 — Group: delete from the conversation-row context menu and confirm

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once real row-menu delete taps are runner-covered; adjacent single-chat sibling is S119
**Status**: covered — LIVE-VALIDATED 2026-06-08 by the real-UI gate (the prior "MIS-SPECIFIED (row persists)" claim was STALE/wrong). The `group_menu_delete_confirm` gate (`drive_real_ui_pair.dart`, campaign `group-menu`) verifies the keyed Delete item renders, dispatches Delete via `l3_open_conversation_menu` `action:'delete'` (avoiding the PopupMenuItem double-fire that the spec mis-attributed to a "row persists" semantic), taps the REAL confirm dialog (`delete_conversation_confirm_button`, which carries a `ModalRoute.isCurrent` double-fire guard), and asserts the group row LEAVES the sidebar. **Live: PASS (gid=tox_4) — the row IS removed.** The reason: the platform `deleteConversation` (`tim2tox_sdk_platform.dart:4087-4103`) fires `onConversationDeleted`, and the host records the id in its SDK-deleted set which SUPPRESSES the row until a new inbound message arrives, AND clears history + pin via `conversationManager.deleteConversation`. So "delete → conversation gone" HOLDS for a group (the row reappears only on the next inbound, the standard delete-conversation behaviour). The earlier reading missed the `onConversationDeleted` suppression and only saw the `fake_im` knownGroups re-emit. Shared desktop+mobile (the delete path + dialog are platform-agnostic). See [[real_ui_group_message_fresh_nontest]].

## Precondition
- Group `<gidG>` is visible in the chats list with non-empty history.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidG>")`.
2. Tap the delete action.
3. Confirm through the surfaced confirm dialog.
4. Re-read the row and conversation state.

## Assertions
- The delete/confirm surface mounts from the real row menu.
- The group conversation row reflects the post-delete behavior expected by the shared conversation manager path.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of S119, but it intentionally targets the conversation-row menu rather than the profile clear/leave rows.
- Exact end-state depends on whether the product interprets delete as clear-history or row removal for groups.
