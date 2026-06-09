# S127 — Group: create a private group from Add Group dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once `AddGroupDialog` segment selection is real-ui driven; adjacent data-half is S32
**Status**: covered — **live-validated 2026-06-08** by the `group_create` real-UI gate (`drive_real_ui_pair.dart` `runGroupCreate`, default `groupType:'private'`): A opens the REAL add-group dialog, selects the keyed Private segment (`add_group_type_private_segment`), types the name, taps Create (`add_group_create_submit_button`), and the new PRIVATE group conversation appears. Runner: `--real-ui-campaign=group-create` (`PASS: real-UI group create+open+composer-send ... type=private`).

## Precondition
- One signed-in account A is Online.
- `AddGroupDialog` is reachable from `new_entry_menu_button` -> `new_entry_create_group_item`.

## UI Driver
1. Open `AddGroupDialog`.
2. Enter a unique private-group name into `UiKeys.addGroupCreateNameInput`.
3. Switch `UiKeys.addGroupTypeSelector` from Public to Private by label/ref.
4. Tap the create CTA.
5. Return to the chats list and inspect the created row.

## Assertions
- A new private group row appears under `UiKeys.groupListTile("<gidG>")`.
- The create path resolves to S32's private-group branch rather than public/conference.
- No runtime errors appear vs baseline.

## Notes
- This is the real-ui selector counterpart to S32's private create variant.
- Per-segment keys are still missing on the segmented control, so runner work is still owed.
