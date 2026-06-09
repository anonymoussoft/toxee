# S126 — Group: create a public group from Add Group dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once a real-ui single-process runner covers `AddGroupDialog`; adjacent data-half is S32
**Status**: covered (infra) — the `group_create` real-UI gate (`drive_real_ui_pair.dart` `runGroupCreate`, live-validated 2026-06-08) drives the REAL add-group dialog → create → open → composer-send. The Public segment is now keyed (`add_group_type_public_segment`, KeyedSubtree wrapper) and selectable via `_createGroupViaUI(groupType:'public')`; the default gate run creates PRIVATE (S127), so the PUBLIC create path is gate-ready but not the default-driven type. Runner: `--real-ui-campaign=group-create`.

## Precondition
- One signed-in account A is Online and the Chats shell is mounted.
- The New Entry menu opens through `UiKeys.newEntryMenuButton` and exposes `UiKeys.newEntryCreateGroupItem`.

## UI Driver
1. Open `AddGroupDialog`.
2. Enter a unique name into `UiKeys.addGroupCreateNameInput`.
3. Leave `UiKeys.addGroupTypeSelector` on the default Public segment.
4. Tap the create CTA.
5. Observe the new group row and the post-create affordance.

## Assertions
- A public group is created and a row keyed as `UiKeys.groupListTile("<gidG>")` becomes visible.
- The create path follows S32's public-group branch, not the private/conference branch.
- No runtime errors appear vs baseline.

## Notes
- Real-ui sibling of S32's create data-half.
- `add_group_type_selector` still lacks per-segment keys, so label/ref fallback is part of the owed runner work.
