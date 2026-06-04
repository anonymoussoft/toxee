# S123 — Group profile: Leave group button (real tap, owner/dissolve case)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG(self-created → A is OWNER)]`
**Harness mode**: peerHarness=none (creator leaving its OWN group resolves the local group_number without a peer — same single-instance property as the `l3_leave_group` gate)
**Promotion target**: L1 WidgetTester for the leave-button-tap → confirm-dialog state machine; the leave DATA round-trip is hermetic-gated by `l3_leave_group.json`.
**Status**: covered (data-half `l3_leave_group.json` proves the leave STATE; the real-UI dissolve-button TAP is an L3 / L1 WidgetTester candidate, NOT itself executable). This is the real-UI upgrade of S35's `l3_leave_group` data path.

> Real-UI upgrade of S35. S35's data-half gate `l3_leave_group.json` drives `l3_leave_group` → `FfiChatService.quitGroup` → native `tox_group_leave` directly. S123 opens the group profile and taps the keyed LEAVE row. Because the hermetic seed `l3_create_group` makes A the **OWNER of a non-Work group**, the UI resolves to the **dissolve** branch: leave row → `_showQuitGroupDialog` → confirm → `dismissGroup` (`lib/ui/group/group_builder_override.dart:747`,`:754`). The eager local cleanup after `result.code==0` is shared with the member-`quit` branch, so the observable end-state is identical.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- One signed-in account A; one **self-created** group `<gidG>` → A is the **OWNER**. `_checkIfQuitGroup` (`group_builder_override.dart:668-673`) sets `quitGroup=false` iff `groupType != GroupType.Work && role == V2TIM_GROUP_MEMBER_ROLE_OWNER`; an NGC group created via `l3_create_group` is non-Work and owned by A, so `quitGroup=false` → the lower row labels `tL10n.dissolve` (`:827`) and `_handleQuitGroup` calls `dismissGroup` (`:754`). The member `quit`/`quitGroup` branch (`quitGroup` stays its default `true`, `:660`) requires A to have JOINED a peer's group (role != OWNER) → that needs TWO processes (Fixture C: see S33 join + S35), **out of scope for this hermetic single-instance scenario**. Both branches hit the SAME keyed widget `UiKeys.groupProfileLeaveButton` (`:816`) and the SAME `_handleQuitGroup`, so the local end-state is identical regardless of role.
- Hermetic seed: `l3_create_group {name:'S123 leave'}` → `<gidG>`; verify `l3_dump_state.knownGroups` contains `<gidG>` (`l3_debug_tools.dart:3672`) and `conversationIds` contains `group_<gidG>` (`:3659`).
- Account A logged in, plaintext, sidebar Online (poll `<nick>\nOnline` ≤60s).
- `MCP_BINDING=marionette` — the header tap opening the group profile has no label; the leave row is keyed.

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart   # includes tool/mcp_test/scenarios/l3_leave_group.json
```

`l3_leave_group.json` is the hermetic hard gate for the leave STATE (S35): `wait_for knownGroups == []` → `create_group` (saveAs gid) → `wait_for knownGroups contains {{gid}}` → `leave_group {groupId:{{gid}}}` → `wait_for knownGroups == []`, asserting `knownGroups notContains {{gid}}`. It drives `l3_leave_group` → `ffi.quitGroup` (`tox_group_leave`) directly, bypassing the profile UI. The stronger sibling `l3_group_leave_clears_all.json` additionally asserts the gid leaves BOTH `knownGroups` AND `conversationIds`. S123 below adds the REAL leave-button tap on top of that proven state path; there is no runnable gate for the marionette profile-open + leave-tap itself (the L1 promotion target above). Note the SDK call differs by role: the gate drives `quitGroup`, the hermetic owner-UI path here drives `dismissGroup` — see Assertions A3 for why both reach the same observable.

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)`; baseline `official.get_runtime_errors({})`. Confirm `l3_dump_state.knownGroups` contains `<gidG>` and `conversationIds` contains `group_<gidG>`.
2. Tap the group row by `UiKeys.groupListTile("<gidG>")` (`group_list_tile:<gidG>`, `ui_keys.dart:157`); ref/label fallback.
3. Tap the chat panel header → pushes `TencentCloudChatGroupProfile` (no key; tap by ref).
4. Tap `UiKeys.groupProfileLeaveButton` (`group_profile_leave_button`) — the **lower** destructive row. For this owner-of-non-Work seed the label is `tL10n.dissolve` (`lib/ui/group/group_builder_override.dart:827`). NOT the upper clear-history row (S122). Fires `_showQuitGroupDialog`. (The SAME key + handler serves the member-`quit` label too; only the role differs.)
5. The confirm dialog mounts; for the owner case the title is `tL10n.dismissGroupTip` (`group_builder_override.dart:730`). Tap the `tL10n.confirm` TextButton (`:737`) — pops `true` and fires `_handleQuitGroup`, which takes the `quitGroup==false` → `dismissGroup` branch (`:753-755`).
6. After UI settles (≤15s), poll `l3_dump_state`.

## Assertions
- A1 (owner baseline): Step 1 — `l3_dump_state.knownGroups` contains `<gidG>`; `conversationIds` contains `group_<gidG>`; `official.get_runtime_errors({})` empty.
- A2 (confirm dialog mounts): after Step 4, a dialog with title `dismissGroupTip` (owner case) is in the tree, with cancel + confirm TextButtons (`group_builder_override.dart:732-742`).
- A3 (left knownGroups, primary): after Step 6, `l3_dump_state.knownGroups` no longer contains `<gidG>` (`l3_debug_tools.dart:3672`). This is `_handleQuitGroup` → `dismissGroup` (code==0) → eager `Prefs.addQuitGroup(gid)` (`group_builder_override.dart:765`) + `conversationManager.deleteConversation('group_<gidG>')` (`:774`). Same end-state as `l3_leave_group.json` via a **PARALLEL path**: the UI owner-dissolve calls `dismissGroup`, the gate calls `quitGroup` — different SDK calls, but BOTH reach `knownGroups`-empty through the shared eager `addQuitGroup`+`deleteConversation` at `:765`/`:774`.
- A4 (conversation removed, primary): `l3_dump_state.conversationIds` no longer contains `group_<gidG>` (`:3659`) — the eager `deleteConversation` strips the row. This is the strictly-stronger half that `l3_group_leave_clears_all.json` also asserts; it distinguishes leave/dissolve (S123) from clear-history (S122, which KEEPS the conversation).
- A5: `official.get_runtime_errors({})` matches the Step-1 baseline; negative grep: `[GroupProfile] _handleQuitGroup: addQuitGroup failed` / `deleteConversation failed` (`group_builder_override.dart:768`/`:779`) MUST NOT appear (log only on failure).

## Notes
- L3-pin reason: the marionette header-tap → profile-push → leave-tap → confirm gesture chain is not a runnable gate; the leave STATE is gated hermetically by `l3_leave_group.json` (S35). S123 is the bridge — assert the same `knownGroups`/`conversationIds` end-state after the real button tap.
- Role caveat: this hermetic single-instance seed only reaches the OWNER/`dissolve`/`dismissGroup` branch (A self-created the group). The member-`quit`/`quitGroup` branch (role != OWNER) requires A to have JOINED a peer's group → a two-process Fixture C setup (cross-ref S33 join + S35), which is out of scope here.
- Key verified: `groupProfileLeaveButton` @ `lib/ui/group/group_builder_override.dart:816` (defined `ui_keys.dart:173`); confirm dialog `_showQuitGroupDialog` @ `:727`, owner title `dismissGroupTip` (`:730`); leave-row label `dissolve` (`:827`); `dismissGroup` call (`:754`).
- Sibling distinction: S35 = hermetic `l3_leave_group` data-half (+ cold-restart `RejoinKnownGroups` invariant via kill/relaunch); S123 = real leave-button tap (owner/dissolve case) of the SAME end-state; S122 = clear-history (upper row, keeps conversation).
- Mobile parity: the leave row lives in the SHARED `_ToxeeGroupProfileDeleteButton` (`lib/ui/group/group_builder_override.dart`), so the keyed control + `_handleQuitGroup` path (both `dismissGroup` and `quitGroup` branches) covers mobile. The confirm dialog is `CupertinoAlertDialog` on macOS (`showAdaptiveDialog`).
