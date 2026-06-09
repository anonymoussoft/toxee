# S105 — Settings: Export-account option chooser

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A profileCrypt=plain autoLogin=on network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate for the CHOOSER SURFACE (REAL_UI_GATES recipe §47 + `MaterialApp` delegates): pump the settings Account card, `tester.tap(find.byKey(UiKeys.settingsExportAccountButton))`, `pumpAndSettle`, assert both `find.byKey(UiKeys.settingsExportProfileToxOption)` and `find.byKey(UiKeys.settingsExportFullBackupOption)` `findsOneWidget`, and that tapping the `.tox` tile pops `'tox'`. The SAVE-DIALOG leg (`FilePicker.platform.saveFile` / the file write) is L3-only, exactly like S43 — it cannot be driven by the runner.
**Status**: covered (L1 WidgetTester real-UI gate — `test/ui/settings/settings_export_chooser_real_ui_test.dart` — chooser surface + 'tox' pop). The gate pumps the production `SettingsPage` Account card with a recording `FfiChatService` stub, taps the REAL `settingsExportAccountButton` (its `onPressed: _showExportOptions`), asserts BOTH keyed option tiles + the "Export Account" chooser title render (A1/A3), then taps the REAL `settingsExportProfileToxOption` and asserts the chooser is dismissed AND the chooser route's `popped` future resolves to `'tox'` (A2 — the value that routes `_exportAccount`). The native save/file-write leg stays L3 (cross-ref S43): the gate arms the in-repo L3 export-save override (`debugSetL3TestSurfaceEnabledForTests` + `debugSetExportSaveFileOverridePathForTests`) so `runL3AwareExportSaveFilePicker` short-circuits before `FilePicker.platform.saveFile` (NSSavePanel) can fire — the file existence / `toxEsave` magic / success-SnackBar assertions remain S43's (A4).
**Covered-by**: `test/ui/settings/settings_export_chooser_real_ui_test.dart`

## Precondition
- One signed-in account A on HomePage; Settings reachable via `sidebarSettings` (`UiKeys.sidebarSettings`, `sidebar_settings_tab`).
- Export button keyed: `settingsExportAccountButton` (`settings_export_account_button`, `lib/ui/settings/settings_page_build.dart:168`), `onPressed: _showExportOptions` (`:173`).
- Chooser tiles keyed: `settingsExportProfileToxOption` (`settings_export_profile_tox_option`, `lib/ui/settings/settings_page.dart:341`, pops `'tox'` at `:347`) and `settingsExportFullBackupOption` (`settings_export_full_backup_option`, `:350`, pops `'zip'` at `:356`).
- Chooser surface is responsive: a `showModalBottomSheet` on mobile (`ResponsiveLayout.isMobile == true`, `settings_page.dart:368-380`) vs a centered `showDialog` on desktop/tablet (`:381+`). Both render the SAME two keyed `ListTile`s via `buildOptions`.
- `MCP_BINDING=marionette`. For the (L3-only) save leg, S43's `l3_set_export_save_path` sandbox-path seam applies; this scenario asserts the CHOOSER, so the save path is optional.

## UI Driver
1. Wait for `<nicknameA>\nOnline` (≤60s poll); baseline `official.get_runtime_errors({})`.
2. `marionette.tap` `UiKeys.sidebarSettings` (`sidebar_settings_tab`).
3. `marionette.tap` `UiKeys.settingsExportAccountButton` (`settings_export_account_button`, `settings_page_build.dart:168`) → `_showExportOptions` opens the chooser (bottom sheet on mobile / Dialog on desktop).
4. Snapshot — assert BOTH option tiles are present (A1).
5. `marionette.tap` `UiKeys.settingsExportProfileToxOption` (`settings_export_profile_tox_option`) → pops `'tox'` → `_exportAccount`. The native macOS save panel (or the `l3_set_export_save_path` override on canonical L3 launches) is reached next — that leg is L3 / S43.

## Assertions
- A1 (primary): after Step 3, the snapshot contains EXACTLY the two keyed chooser tiles — `settings_export_profile_tox_option` (label `exportOptionProfileTox` = "Profile (.tox)", `app_en.arb:995`) AND `settings_export_full_backup_option` (label `exportOptionFullBackup` = "Full Backup (.zip)", `app_en.arb:1000`). Both are tappable `ListTile`s.
- A2: tapping `settings_export_profile_tox_option` dismisses the chooser (it `Navigator.of(ctx).pop('tox')`, `settings_page.dart:347`); the chooser surface disappears from the snapshot. The pop VALUE `'tox'` is what routes `_exportAccount` to the profile path (asserted directly in the L1 promotion gate; over MCP it's observed as "chooser dismissed → save flow begins").
- A3: the chooser title is `exportAccount` = "Export Account" (`settings_page.dart:335`) — the same label reused as the button (A1's parent) and the eventual `saveFile` dialogTitle; disambiguate by role/parent (S43 note).
- A4 (save leg — cross-ref S43, L3-only): after the `'tox'` pop, the native save dialog (or `l3_set_export_save_path` override) handles the write; the file-existence + `toxEsave`-magic + success-SnackBar assertions are S43's (A3–A7). S105 does NOT re-assert them — it owns the CHOOSER surface only.
- A5: `official.get_runtime_errors({})` empty vs the Step-1 baseline.

## Notes
- L3-pin reason: the chooser itself is L1-promotable (the recipe in Promotion target); the scenario is L3 only because its terminal action (the save dialog / file write) is the native picker, which is L3 per UI_TEST_LAYERING §3 ("Native file picker → L3 only") and is already documented by S43.
- Key status (verified): `settingsExportAccountButton` @ `settings_page_build.dart:168`; `settingsExportProfileToxOption` @ `settings_page.dart:341`; `settingsExportFullBackupOption` @ `:350`. All shipped — this CLOSES the S43 §Notes gap ("Wanted key `settingsExportAccountButton` is NOT in `ui_keys.dart`; tap by label today" and "Same for the chooser tiles"); S105 is the keyed upgrade of S43's Step 3–4.
- Sibling distinction: S43 is the full export→native-save→file-write playbook (S43a plaintext / S43b encrypted). S105 isolates the CHOOSER (the two keyed options + the `'tox'` pop) and stops at the picker boundary, deferring the write to S43.
- Gotcha: the `'zip'` branch (`_exportFullBackup`) is S43c-deferred — same native save dialog, no per-format password gate. S105 asserts the zip option is PRESENT (A1) but drives only the `.tox` tile.
- Mobile parity: `_showExportOptions` + both tiles + `_exportAccount` are shared Dart (`lib/ui/settings/`); only the chooser CONTAINER forks (bottom sheet on mobile vs Dialog on desktop, `settings_page.dart:368-381`), and both render the same two keyed tiles, so A1/A2 hold on both. The native save dialog differs per platform (S43 territory).
