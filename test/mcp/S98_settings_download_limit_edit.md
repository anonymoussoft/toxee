# S98 — Settings: edit Download-Size-Limit field + Save (real input)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK) platform=macOS`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate (REAL_UI_GATES recipe) — `enterText` + tap Save runs `int.tryParse` validation + `Prefs.setAutoDownloadSizeLimit`, expressible behind the `GlobalSettingsSection` seam (real `Prefs`, stub service) over `TestWidgetsFlutterBinding`. L3 today only because the real-input path is unvalidated.
**Status**: covered (data-half gate exists; the UI input is L3, authored-as-target only). This is the REAL-INPUT UPGRADE of **S87** (`l3_download_limit_toggle.json`), whose `l3_set_setting autoDownloadSizeLimit` int round-trip is the proven hard gate.

## Precondition
- Account A signed in, plaintext profile; `Prefs.getAutoDownloadSizeLimit()` (GLOBAL int MB; read at `lib/ui/settings/global_settings_section.dart:158`) currently `30` — the macOS seeded default (mobile default is 5).
- `l3_dump_state.autoDownloadSizeLimit == 30` at baseline (the gate's first `state_equals` step fails loudly on a dirty fixture).
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`, run `MCP_BINDING=marionette ./run_toxee.sh`.

## Executable Driver

```bash
# REAL-UI input gate (authored as target; nonBlocking — live-validation + codex-review OWED):
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_settings_downloadlimit_tap.json

# PROVEN data-half (S87, passes today): drives l3_set_setting autoDownloadSizeLimit (30->13->30)
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_download_limit_toggle.json
```

The input gate `enter_text`s `"13"` into the REAL field (`UiKeys.settingsDownloadLimitField`), taps Save (`UiKeys.settingsDownloadLimitSaveButton`), proves `autoDownloadSizeLimit` flips to 13 in `l3_dump_state`, then re-enters `"30"` + Save to restore. It is `nonBlocking:true` (first use of `enter_text`/`tap`; unresolved marionette-ext/binding) — failures report FLAKY. The proven gate is the S87 data-half `l3_download_limit_toggle.json`, driving the same int `Prefs` round-trip via `l3_set_setting`. The proper stable executable form is likely an L1 WidgetTester gate.

## UI Driver
1. `marionette.tap(UiKeys.sidebarSettings)` (`sidebar_settings_tab`) — open the Settings screen.
2. (If below the fold) scroll to the Auto Download Size Limit card — the JSON runner has NO scroll action (real blocker under the runner); under a live marionette session use `mcp__marionette__scroll_to`.
3. `marionette.enter_text(UiKeys.settingsDownloadLimitField, "13")` (`settings_download_limit_field`) — the numeric `TextField` at `lib/ui/settings/global_settings_section.dart:611`.
4. `marionette.tap(UiKeys.settingsDownloadLimitSaveButton)` (`settings_download_limit_save_button`) — the Save `ElevatedButton` at `:640`; `onPressed` → `_saveAutoDownloadSizeLimit` (`:164`), which validates `1..10000` then `Prefs.setAutoDownloadSizeLimit(limit)`.
5. Poll `l3_dump_state.autoDownloadSizeLimit` ≤5s for `13`.
6. `marionette.enter_text(UiKeys.settingsDownloadLimitField, "30")` then `marionette.tap(UiKeys.settingsDownloadLimitSaveButton)` — RESTORE to 30 within the same run.

## Assertions
- A1 (baseline): `l3_dump_state.autoDownloadSizeLimit == 30` before any input.
- A2 (flip): after Step 4, `l3_dump_state.autoDownloadSizeLimit == 13` — reflects `_saveAutoDownloadSizeLimit`'s `Prefs.setAutoDownloadSizeLimit(13)` write (`global_settings_section.dart:168`). 13 passes the `limit > 0 && limit <= 10000` guard (`:167`).
- A3 (restore, final): after Step 6, `l3_dump_state.autoDownloadSizeLimit == 30` — the gate's terminal `state{equals:30}`; self-cleans ON SUCCESSFUL COMPLETION only (no `teardown` phase — a mid-run failure/interruption can leave the setting flipped; re-run or restore manually).
- A4 (validation guard, optional): entering a non-positive or `>10000` value leaves `autoDownloadSizeLimit` unchanged (the `int.tryParse` + range guard short-circuits the write) — not asserted by the happy-path gate; a candidate L1 edge-case test.

## Notes
- L3-pin reason: real-input mechanism unproven; L1 promotion gated on validating the marionette `enterText`/`tap` exts. Keys verified wired at `lib/ui/settings/global_settings_section.dart:611` (field) and `:640` (save button).
- Sibling distinction: **S87** is the DATA half (`l3_set_setting` int round-trip, proven); S98 is the REAL field-edit + Save of the same setting.
- The Save handler clamps to `1..10000` MB and silently ignores invalid input (no SnackBar) — the assertion is the `l3_dump_state` int, not a UI confirmation.
- Below-the-fold gotcha: the field + Save button sit well below the fold (Auto Download Size Limit is near the bottom of the Global Settings list); the scroll-less JSON runner cannot reach them even with a working marionette binding.
