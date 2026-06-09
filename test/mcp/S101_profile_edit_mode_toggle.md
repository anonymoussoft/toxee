# S101 — Self-profile: enter/exit edit-mode toggle

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 profileCrypt=plain autoLogin=on network=any (Offline OK) history=don't-care`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate (REAL_UI_GATES recipe §47 "render fork chat widgets" — though this needs only `MaterialApp` + `AppLocalizations`/`TencentCloudChatLocalizations` delegates, no fork chat widget). The toggle→edit→save closure is ALREADY exercised by `test/ui/profile_edit_persists_to_account_list_test.dart:156-198` (fires `UiKeys.profileEditToggle.onPressed`, edits `profileNicknameField`/`profileStatusField`, taps `profileSaveButton`); the only missing L1 leg is the toggle-again-EXITS-edit-mode assertion (`_editMode` flips back to read-only), which that test does not cover. Promote by extending that test with a second toggle tap + `findsNothing` on the edit fields.
**Status**: covered (L1 WidgetTester real-UI gate — test/ui/profile_open_and_edit_toggle_real_ui_test.dart). Marionette live-round-trip (A2 statusMessage l3_dump_state assertion) remains L3-only.
**Covered-by**: test/ui/profile_open_and_edit_toggle_real_ui_test.dart
**Mobile parity**: the edit toggle, edit fields, and save button all live in shared Dart (`lib/ui/profile/profile_header.dart`, `lib/ui/profile/profile_edit_fields.dart`, `lib/ui/profile_page.dart`). The L1 gate covers iOS/Android identically; the only platform fork is Dialog vs fullscreen route (both in `sidebar.dart`), orthogonal to the toggle assertions.

## Precondition
- Account A signed in, plaintext profile (`_StartupGate` lands on HomePage, not the password dialog).
- Self-profile is editable: `showSelfProfile` builds `ProfilePage(isEditable: true, …)` (`lib/ui/settings/sidebar.dart:62-66`), so the header renders the edit toggle (`if (isEditable)` guard at `lib/ui/profile/profile_header.dart:106`).
- Status message starts empty so the round-trip is a fresh write, not a no-op (the `l3_self_profile_toggle.json` gate enforces this START invariant). Wire key `flutter.self_status_msg` (`lib/util/prefs.dart`).
- `MCP_BINDING=marionette`, app built `--dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`.

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_self_profile_toggle.json
```

This is the DATA half only: it sets the own `statusMessage` via `l3_set_self_profile` (which rides the real `FfiChatService.updateSelfProfile` + `Prefs.setStatusMessage` path that the Save button's `onSave` closure calls — `sidebar.dart:70-84`) and proves it round-trips through `l3_dump_state.statusMessage`, with the nickname PRESERVED (the test-account nickname guard). It does NOT tap the edit toggle, type into the fields, or assert the edit-mode flip — those are the UI Driver below, and there is no marionette-driven runnable gate for them yet.

## UI Driver
1. `marionette.tap` `UiKeys.sidebarUserAvatar` (`sidebar_user_avatar`) → `_openProfile` (`sidebar.dart:401`) → `ProfilePage` mounts (desktop Dialog / mobile fullscreen route).
2. `marionette.tap` `UiKeys.profileEditToggle` (`profile_edit_toggle`) — the header pencil `IconButton` (`profile_header.dart:108`). Flips `_editMode = true`; mounts `ProfileEditFields` (the two `TextField`s + Cancel + Save).
3. `marionette.enter_text` `UiKeys.profileStatusField` (`profile_status_field`, `profile_edit_fields.dart:89`) with `"S101 edit-mode status"`. (Nickname `UiKeys.profileNicknameField` `profile_nickname_field` at `:78` exists but is intentionally NOT mutated — same test-account-guard reasoning as S8.)
4. `marionette.tap` `UiKeys.profileSaveButton` (`profile_save_button`, `profile_edit_fields.dart:112`). Runs `_handleSave` → `onSave` closure → `updateSelfProfile` + `Prefs.setStatusMessage` + `setState(() => _editMode = false)`.
5. `marionette.tap` `UiKeys.profileEditToggle` AGAIN — re-enter edit mode (the icon is now `Icons.close`, tooltip `cancelTooltip`). Then tap it once more to confirm the toggle is bidirectional: edit fields unmount, header returns to read-only.

## Assertions
- A1: after Step 2, the snapshot contains `UiKeys.profileNicknameField` + `UiKeys.profileStatusField` + `UiKeys.profileSaveButton` keys (edit mode entered). The header pencil icon is `Icons.close` (tooltip = `cancelTooltip`, `profile_header.dart:109-110`).
- A2: after Step 4 (Save), `l3_dump_state.statusMessage` == `"S101 edit-mode status"` (the round-trip the executable gate also asserts, here driven by the real tap).
- A3: after Save, the edit fields UNMOUNT — the snapshot no longer contains `UiKeys.profileSaveButton`; the header pencil icon is back to `Icons.edit` (tooltip = `editTooltip`). This is the `setState(() => _editMode = false)` flip in `_handleSave`.
- A4: after the final Step 5 toggle, the snapshot again has NO `profileSaveButton` (toggle off works without a save). Re-tapping `profileEditToggle` from read-only re-mounts the fields (toggle is a pure `_editMode` flip — `onToggleEdit` at `profile_header.dart:111`).
- A5: `idCopiedToClipboard` / any copy snackbar MUST NOT appear (this scenario never copies); a success "Saved" snackbar (`AppSnackBar.showSuccess`) MAY appear after Step 4.
- A6: `official.get_runtime_errors({})` empty vs the Step-1 baseline.

## Notes
- L3-pin reason: only the toggle-EXIT leg (A3/A4) is missing at L1; the enter+edit+save path is already a passing WidgetTester gate (`profile_edit_persists_to_account_list_test.dart`). This spec is the marionette UI-tap upgrade + the promotion pointer.
- Key status (verified): `profileEditToggle` @ `profile_header.dart:108`; `profileNicknameField` @ `profile_edit_fields.dart:78`; `profileStatusField` @ `:89`; `profileSaveButton` @ `:112`. All shipped.
- Sibling distinction: S8 is the heavy nickname+status+blob+account_list persistence playbook; S101 isolates the `_editMode` TOGGLE state machine (enter AND exit) — the one axis S8/`l3_self_profile_toggle` don't assert.
- Gotcha: `_handleSave` does NOT pop the dialog on success — it only flips `_editMode` to false. The dialog stays mounted in read-only mode (same as S8 Step 7); A3 observes that read-only state, not a dismissal.
- Mobile parity: the edit toggle + fields + save are shared Dart (`lib/ui/profile/*`), identical on the mobile fullscreen `MaterialPageRoute` — the only difference is the Dialog-vs-route container in `sidebar.dart`. The toggle assertions hold on both.
