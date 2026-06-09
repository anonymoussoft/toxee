# S138 — Group: edit the group name from the profile dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG owner] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once the profile edit pencil/dialog flow is runner-covered; adjacent data-half sibling is S32/S153
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the toxee edit button, fills the rename field, confirms, and asserts the displayed name updates after a successful `setGroupInfo` platform call.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- Group owner account A has `<gidG>` openable in the profile.
- The profile header shows the name plus the edit pencil.

## UI Driver
1. Open the group profile.
2. Tap `UiKeys.groupProfileEditNameButton` (`group_profile_edit_name_button`) next to the displayed group name.
3. Enter a new group name into `UiKeys.groupProfileEditNameField` (`group_profile_edit_name_field`).
4. Confirm via `UiKeys.groupProfileEditNameConfirmButton` (`group_profile_edit_name_confirm_button`).

## Assertions
- The confirm path updates the displayed group name in the profile.
- The rename routes through the real group profile dialog, not a debug seam.
- No runtime errors appear vs baseline.

## Notes
- The dialog is implemented in toxee's override layer and is separate from the upstream default builder path.
- A later row-refresh case tracks propagation back to the chats list.
- Key status: the toxee content override now exposes stable `group_profile_edit_name_button`, `group_profile_edit_name_dialog`, `group_profile_edit_name_field`, and `group_profile_edit_name_confirm_button` anchors for this flow.
