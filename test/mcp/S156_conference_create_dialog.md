# S156 — Conference: create a legacy conference from Add Group dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once `AddGroupDialog` segment selection is real-ui driven; adjacent data-half is S32
**Status**: covered — **live-validated 2026-06-08** by the `conference_message` real-UI gate (`drive_real_ui_pair.dart`, `groupType:'conference'`): A opens the REAL add-group dialog, selects the keyed Conference segment (`add_group_type_conference_segment`), types a name, taps Create → a legacy Tox conference is created (`tox_conference_new`; conversation id `tox_conf_0_...`). Runner: `--real-ui-campaign=accepted-friend-inline-conference-message`.
**Covered-by**: `test/ui/conference/conference_create_dialog_real_ui_test.dart`

## Precondition
- One signed-in account A is Online and the Chats shell is mounted.
- `AddGroupDialog` is reachable from the New Entry menu.

## UI Driver
1. Open `AddGroupDialog`.
2. Enter a unique conference name into `UiKeys.addGroupCreateNameInput`.
3. Switch `UiKeys.addGroupTypeSelector` to the Conference segment.
4. Tap the create CTA.
5. Return to the chats list and inspect the created row.

## Assertions
- A new conference row appears and is targetable by `UiKeys.groupListTile("<gidC>")`.
- The create path resolves to the conference branch rather than public/private group creation.
- No runtime errors appear vs baseline.

## Notes
- This is the conference-specific create path called out as a branch inside S32.
- The same dialog and row key are reused; only the selected create type differs.
