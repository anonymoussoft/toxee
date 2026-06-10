# S132 — Group: pin / unpin from the conversation-row context menu

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once real row-menu tapping is runner-covered; adjacent data-half siblings are `l3_pin_group_toggle` and S84
**Status**: covered at the widget layer (L1) — the pin/unpin key flip and value:'pin' toggle dispatch for group rows are gated by `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart` (tests "S132 NGC group conversation-row menu pin item key flips with pinned state" and "S132 NGC group pin and unpin items both carry value:pin"). Also LIVE-VALIDATED 2026-06-08 by the real-UI gate (the prior "PARTIAL/retired" status was a HARNESS limitation, not a product gap).
**Covered-by**: `test/ui/conversation/conversation_row_menu_group_real_ui_test.dart` The `group_menu_pin_unpin` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-menu`) creates a group, verifies the keyed pin item renders, then drives Pin → assert `isPinned` → Pin again → assert unpinned through the production `pinConversation` path. The earlier failure was the flutter_skill PopupMenuItem **double-fire** turning the toggle into a net no-op (synthetic pointer + direct `InkWell` callback); the gate now dispatches the menu action deterministically via `l3_open_conversation_menu` `action:'pin'`, which runs the SAME `_dispatchConversationMenuAction` the menu's `onSelected` runs (extracted from `home_page.dart` `_showConversationContextMenu`) — so the toggle fires exactly once. Group pinning remains PRODUCT-CORRECT (menu Pin → `pinConversation` → `conversation_manager_adapter` → group-aware `FakeConversationManager.setPinned`, persisting `group_<normalizedGid>`). **Live: PASS (gid=tox_2).** Shared desktop+mobile (the pin path + the action dispatch are platform-agnostic). See [[real_ui_group_message_fresh_nontest]].

## Precondition
- Group `<gidG>` is visible in the chats list and starts unpinned.

## UI Driver
1. Open the row menu on `UiKeys.groupListTile("<gidG>")`.
2. Tap the pin action.
3. Re-open the row menu and tap unpin.

## Assertions
- The group row moves into and back out of the pinned ordering slot.
- The action modifies the same pinned state used by the group data-half gates.
- No runtime errors appear vs baseline.

## Notes
- This is the real-ui menu counterpart to the existing group pin data-half.
- Menu-item keys are shared with the conversation-row menu family.
