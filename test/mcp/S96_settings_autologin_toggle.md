# S96 — Settings: toggle Auto-Login switch (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK) theme=any`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate (REAL_UI_GATES recipe) — the switch flips a single `setState` + `Prefs.setAutoLogin`, expressible behind the `SettingsPage` constructor seam with a stub `FfiChatService` + real `Prefs` over a `TestWidgetsFlutterBinding`. L3 today only because the real-tap path is unvalidated (see Notes).
**Status**: covered READ-ONLY (`l3_session_settings.json` reads `autoLogin`); there is NO write round-trip gate — `l3_set_setting` REJECTS `autoLogin` (l3_debug_tools.dart:1790,1904). The real-UI switch tap is a `nonBlocking` smoke only (`l3_settings_autologin_tap.json`), unvalidated.

## Precondition
- Account A signed in, plaintext profile; `Prefs.getAutoLogin(toxId)` (per-account, wire key `auto_login` family read at `lib/ui/settings/settings_page.dart:155`) currently `true` — the seeded fixture default and the harness's own auto-login source.
- `l3_dump_state.autoLogin == true` at baseline (the runner's first `state_equals` step fails loudly on a dirty fixture).
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`, run `MCP_BINDING=marionette ./run_toxee.sh`.

## Executable Driver

```bash
# REAL-UI tap gate (authored as target; nonBlocking — live-validation + codex-review OWED):
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_settings_autologin_tap.json

# PROVEN data-half (read-only, passes today): asserts l3_dump_state.autoLogin == true
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_session_settings.json
```

The tap gate proves the REAL switch (`UiKeys.settingsAutoLoginSwitch`) flips `autoLogin` in `l3_dump_state` and restores it. It is `nonBlocking:true` because it is the suite's first use of the `tap` action and the marionette-ext/binding question is unresolved — a failure reports FLAKY, not FAIL (`run_l3_scenarios.dart:282,300`). The actually-passing gate today is the data-half `l3_session_settings.json` (read-only `autoLogin == true`). The autoaccept toggles (`l3_autoaccept_friend_toggle.json`) prove the `set_setting` MECHANISM EXISTS, but `autoLogin` itself is NOT a drivable key — `l3_set_setting` REJECTS it (allowlist `{autoAcceptFriends, autoAcceptGroupInvites, notificationSound}` @ l3_debug_tools.dart:1896-1900; rejection documented @ :1790, error @ :1904-1909). So NO write round-trip gate exists for `autoLogin`; only the read-only `l3_session_settings.json` passes today. The proper stable executable form is likely an L1 WidgetTester gate, not this JSON.

## UI Driver
1. `marionette.tap(UiKeys.sidebarSettings)` (`sidebar_settings_tab`) — open the Settings screen.
2. (If below the fold) scroll the settings list to the Account card's Auto-Login row — the L3 JSON runner has NO scroll action, so under the JSON runner this is a real blocker; under a live marionette session use `mcp__marionette__scroll_to`.
3. `marionette.tap(UiKeys.settingsAutoLoginSwitch)` (`settings_auto_login_switch`) — the `Switch` at `lib/ui/settings/settings_page_build.dart:246`; `onChanged` → `_setAutoLogin(value)` (`settings_page.dart:164`).
4. Poll `l3_dump_state.autoLogin` ≤5s for `false`.
5. `marionette.tap(UiKeys.settingsAutoLoginSwitch)` again — RESTORE to `true` within the same run (see autoLogin caveat in Notes).

## Assertions
- A1 (baseline): `l3_dump_state.autoLogin == true` before any tap.
- A2 (flip): after Step 3, `l3_dump_state.autoLogin == false` — the field sourced from `Prefs.getAutoLogin` reflects `_setAutoLogin`'s `Prefs.setAutoLogin(value, toxId)` write (`settings_page.dart:170`).
- A3 (restore, final): after Step 5, `l3_dump_state.autoLogin == true` — the gate's terminal `state{equals:true}` assertion; the fixture self-cleans ON SUCCESSFUL COMPLETION only (no `teardown` phase — a mid-run failure/interruption can leave the setting flipped; re-run or restore manually).
- A4 (negative, optional under live marionette): `official.get_runtime_errors({})` empty vs Step-1 baseline.

## Notes
- L3-pin reason: the tap mechanism is unproven; the L1 promotion is gated on validating the marionette `tap` ext under a working binding. Key verified wired at `lib/ui/settings/settings_page_build.dart:246` (`key: UiKeys.settingsAutoLoginSwitch`).
- AutoLogin caveat: toggling `autoLogin` off persists per-account and would affect harness auto-login on the NEXT launch — the gate toggles→asserts→restores within ONE run; the terminal `autoLogin=true` assertion restores it ON SUCCESSFUL COMPLETION only (no `teardown` phase — a mid-run failure/interruption can leave it `false`, breaking harness auto-login on the next launch; re-run or restore manually).
- Sibling distinction: S39 owns the autoLogin persistence-across-restart (L2-promotable) read-half; S96 is the in-session REAL-tap of the switch widget.
- Below-the-fold gotcha: the Auto-Login row is in the Account card; if it is below the fold, the scroll-less JSON runner cannot reach it — a real reason the JSON gate may not pass even once the marionette binding works.
- Mobile parity: the auto-login Switch lives in `lib/ui/settings/settings_page_build.dart` (toxee-owned, shared across platforms) → covers mobile.
