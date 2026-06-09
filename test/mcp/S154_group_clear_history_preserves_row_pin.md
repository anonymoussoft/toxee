# S154 — Group: clear history preserves the row and pin state

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG pinned] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once clear-history plus pin assertions are runner-covered; adjacent sibling is S122
**Status**: covered — LIVE-VALIDATED 2026-06-08 by the two-process real-UI gate. The invariant is now DRIVEN end-to-end, not just asserted by construction: the `group_clear_preserves_pin` gate (`drive_real_ui_pair.dart`, campaign `group-clear-preserves-pin`) establishes a two-process private group, PINS it via the row menu's `pin` action (S132's deterministic `l3_open_conversation_menu` action path), has B send so A holds real history, CLEARS via `l3_clear_group_history` (S122's new tool), then asserts the row remains present AND still pinned AND `messageCount==0`. **Live: PASS (preserved row + pin, gid=tox_1).** This confirms the code-layer invariant: `FfiChatService.clearGroupHistory` (ffi_chat_service.dart:4886) clears only the message-history persistence + the `_lastByPeer`/`_unreadByPeer` maps — it NEVER touches the pinned set (`Prefs` `group_<gid>` key, written by the group-aware `FakeConversationManager.setPinned`). Pin and history are independent stores. Both constituents are also independently live-validated (S132 pin, S122 clear-history). The earlier blockers (retired pin tap-leg + flutter_skill-unreachable profile route) were sidestepped by dispatching the menu/clear actions through deterministic l3 hooks. Shared desktop+mobile. See [[real_ui_group_message_fresh_nontest]].

## Precondition
- Group `<gidG>` starts pinned and has non-empty history.
- The group profile clear-history row is reachable.

## UI Driver
1. Open the group profile.
2. Trigger clear history and confirm.
3. Return to the chats list.

## Assertions
- The group row still exists after clear history.
- The row remains pinned after the clear-history path completes.
- No runtime errors appear vs baseline.

## Notes
- This isolates the “clear without unpinning” contract documented in S122.
- It is a useful regression guard against accidentally routing clear-history through delete-conversation semantics.
