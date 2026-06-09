# S168 — Conference: edit the conference name from the profile dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC host] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once the profile edit pencil/dialog flow is runner-covered; adjacent sibling is S138
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` taps the toxee edit button, fills the rename field, confirms, and asserts the displayed conference name updates after a successful `setGroupInfo` platform call.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference host account A can open the profile for `<gidC>`.
- The profile header shows the name plus the edit pencil.

## UI Driver
1. Open the conference profile.
2. Tap `UiKeys.groupProfileEditNameButton` (`group_profile_edit_name_button`) next to the displayed conference name.
3. Enter a new conference name into `UiKeys.groupProfileEditNameField` (`group_profile_edit_name_field`).
4. Confirm via `UiKeys.groupProfileEditNameConfirmButton` (`group_profile_edit_name_confirm_button`).

## Assertions
- The confirm path updates the displayed conference name in the profile.
- The rename routes through the real profile dialog rather than a debug seam.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S138.
- The dialog is shared across group/conference profile content in toxee's override.
- Key status: the shared toxee content override now exposes stable `group_profile_edit_name_button`, `group_profile_edit_name_dialog`, `group_profile_edit_name_field`, and `group_profile_edit_name_confirm_button` anchors for this flow.
