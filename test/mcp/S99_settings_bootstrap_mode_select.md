# S99 — Settings: Bootstrap-Node mode segmented control (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online platform=macOS`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate for the SETTING write (the `RadioListTile.onChanged` → `Prefs.setBootstrapNodeMode` leg is seam-expressible); the `auto`-mode `BootstrapNodesService.fetchNodes()` network side-effect is L3-only. L3 today because the real-tap path is unvalidated AND tapping `auto` reaches out to the network.
**Status**: covered (data-half gate exists; the UI tap is L3, authored-as-target only). This is the REAL-TAP UPGRADE of **S85** (`l3_bootstrap_mode_toggle.json`), whose `l3_set_setting bootstrapNodeMode` enum round-trip is the proven hard gate.

## Precondition
- Account A signed in, plaintext profile; `Prefs.getBootstrapNodeMode()` (GLOBAL enum `{auto,manual,lan}`) currently `auto` — the seeded default reconciled at `lib/ui/settings/bootstrap_settings_section.dart:85`.
- `l3_dump_state.bootstrapNodeMode == "auto"` at baseline (the gate's first `state_equals` step fails loudly on a dirty fixture).
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`, run `MCP_BINDING=marionette ./run_toxee.sh`.

## Executable Driver

```bash
# REAL-UI tap gate (authored as target; nonBlocking — live-validation + codex-review OWED):
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_settings_bootstrap_mode_tap.json

# PROVEN data-half (S85, passes today): drives l3_set_setting bootstrapNodeMode (auto->manual->auto)
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_bootstrap_mode_toggle.json
```

The tap gate taps the REAL Manual segment (`UiKeys.settingsBootstrapModeManual`), proves `bootstrapNodeMode` flips to `manual` in `l3_dump_state`, then taps Auto to restore. It is `nonBlocking:true` (novel `tap` action + unresolved marionette-ext/binding) — failures report FLAKY. The proven gate is the S85 data-half `l3_bootstrap_mode_toggle.json`, which drives the identical enum `Prefs` round-trip via `l3_set_setting` (the data layer this widget's `onChanged` writes through, minus the network side-effect). The proper stable executable form for the SETTING is likely an L1 WidgetTester gate.

## UI Driver
1. `marionette.tap(UiKeys.sidebarSettings)` (`sidebar_settings_tab`) — open the Settings screen.
2. (If below the fold) scroll to the Bootstrap Nodes section's mode row — the JSON runner has NO scroll action (real blocker under the runner); under a live marionette session use `mcp__marionette__scroll_to`.
3. `marionette.tap(UiKeys.settingsBootstrapModeManual)` (`settings_bootstrap_mode_manual`) — the `RadioListTile<String>` value `'manual'` at `lib/ui/settings/bootstrap_settings_section.dart:1130`; `onChanged` → `_setBootstrapNodeMode('manual')` (`:91`).
4. Poll `l3_dump_state.bootstrapNodeMode` ≤5s for `"manual"`.
5. `marionette.tap(UiKeys.settingsBootstrapModeAuto)` (`settings_bootstrap_mode_auto`, value `'auto'` at `:1146`) — RESTORE to `auto` within the same run.

## Assertions
- A1 (baseline): `l3_dump_state.bootstrapNodeMode == "auto"` before any tap.
- A2 (flip): after Step 3, `l3_dump_state.bootstrapNodeMode == "manual"` — reflects `_setBootstrapNodeMode`'s `Prefs.setBootstrapNodeMode('manual')` write (`bootstrap_settings_section.dart:93`).
- A3 (restore, final): after Step 5, `l3_dump_state.bootstrapNodeMode == "auto"` — the gate's terminal `state{equals:"auto"}`; self-cleans ON SUCCESSFUL COMPLETION only (no `teardown` phase — a mid-run failure/interruption can leave the setting flipped; re-run or restore manually).
- A4 (negative, optional under live marionette): `official.get_runtime_errors({})` empty vs Step-1 baseline (the `auto`-restore fires `BootstrapNodesService.fetchNodes()` at `:96-97` — a transient fetch failure must NOT surface as a runtime error).

## Notes
- L3-pin reason: real-tap mechanism unproven AND the `auto` segment triggers a live `fetchNodes()` network call (`bootstrap_settings_section.dart:96-97`), so the restore leg is not purely hermetic. The SETTING write is L1-promotable; the network side-effect is L3-pinned. Keys verified wired at `:1130` (manual), `:1146` (auto), `:1183` (lan).
- Sibling distinction: **S85** is the DATA half (`l3_set_setting` enum round-trip, proven); S99 is the REAL-tap of the same segmented control. The `lan` segment is desktop-only (`_setBootstrapNodeMode` early-returns on non-desktop, `:92`) and intentionally not exercised here.
- Mobile parity: mobile renders `_buildModeRowMobile` (`:1201`) with the same `_setBootstrapNodeMode` handler and only `manual|auto` (lan hidden); the same key strings are NOT attached to the mobile row today — a real-tap mobile gate would need the keys mirrored onto `_buildModeRowMobile`.
- Below-the-fold gotcha: the mode row is deep in the Bootstrap Nodes section; the scroll-less JSON runner cannot reach it even with a working marionette binding.
