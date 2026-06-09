# S153 — Group: profile rename refreshes the conversation row title

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG owner] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once rename + row-refresh are runner-covered together; adjacent siblings are S138 and S32
**Status**: covered at the widget layer (L1) — `test/ui/chat_core_real_ui_test.dart` "group profile content rename confirm updates the title and calls setGroupInfo" drives the real edit-name dialog (`group_profile_edit_name_button` → `_field` → `_confirm_button`) and asserts the displayed title refreshes to the new name AND the old name is gone (`setGroupInfo` fired). The displayed-TITLE refresh is the widget-layer half of "rename refreshes the row". The conversation-LIST-row refresh half + the two-process `group_rename` driver gate remain blocked on the group-profile-route harness reachability limitation (see S136).

## Precondition
- A owns `<gidG>` and can rename it from the profile dialog.

## UI Driver
1. Rename `<gidG>` through the profile edit dialog.
2. Return to the chats list.
3. Inspect `UiKeys.groupListTile("<gidG>")`.

## Assertions
- The conversation row title refreshes to the renamed group value.
- The rename propagates through the real UI path rather than a direct prefs edit.
- No runtime errors appear vs baseline.

## Notes
- This case follows S138 by checking the downstream list refresh.
- It is a useful parity check against the conversation-list builder's display-name resolution.
