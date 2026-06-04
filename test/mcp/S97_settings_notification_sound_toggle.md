# S97 — Settings: toggle Notification-Sound switch (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK) theme=any`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester candidate (REAL_UI_GATES recipe) — the switch flips a single `setState` + `Prefs.setNotificationSoundEnabled`, expressible behind the `GlobalSettingsSection` constructor seam (real `Prefs`, stub service) over `TestWidgetsFlutterBinding`. L3 today only because the real-tap path is unvalidated.
**Status**: covered (data-half gate exists; the UI tap is L3, authored-as-target only). This is the REAL-TAP UPGRADE of **S86** (`l3_notification_sound_toggle.json`), whose `l3_set_setting notificationSound` round-trip is the proven hard gate.

## Precondition
- Account A signed in, plaintext profile; `Prefs.getNotificationSoundEnabled(toxId)` (per-account; read at `lib/ui/settings/global_settings_section.dart:83`) currently `true` — the seeded default.
- `l3_dump_state.notificationSound == true` at baseline (the gate's first `state_equals` step fails loudly on a dirty fixture).
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`, run `MCP_BINDING=marionette ./run_toxee.sh`.

## Executable Driver

```bash
# REAL-UI tap gate (authored as target; nonBlocking — live-validation + codex-review OWED):
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_settings_notifsound_tap.json

# PROVEN data-half (S86, passes today): drives l3_set_setting notificationSound (true->false->true)
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_notification_sound_toggle.json
```

The tap gate proves the REAL switch (`UiKeys.settingsNotificationSoundSwitch`) flips `notificationSound` in `l3_dump_state` and restores it. It is `nonBlocking:true` (novel `tap` action + unresolved marionette-ext/binding) — a failure reports FLAKY, not FAIL. The proven gate is the S86 data-half `l3_notification_sound_toggle.json`, which drives the identical `Prefs` round-trip via `l3_set_setting` (the data layer this widget's `onChanged` writes through). The proper stable executable form is likely an L1 WidgetTester gate.

## UI Driver
1. `marionette.tap(UiKeys.sidebarSettings)` (`sidebar_settings_tab`) — open the Settings screen.
2. (If below the fold) scroll to the Global Settings section's Notification-Sound row — the JSON runner has NO scroll action (real blocker under the runner); under a live marionette session use `mcp__marionette__scroll_to`.
3. `marionette.tap(UiKeys.settingsNotificationSoundSwitch)` (`settings_notification_sound_switch`) — the `Switch` at `lib/ui/settings/global_settings_section.dart:492`; `onChanged` → `_setNotificationSoundEnabled` (`:87`).
4. Poll `l3_dump_state.notificationSound` ≤5s for `false`.
5. `marionette.tap(UiKeys.settingsNotificationSoundSwitch)` again — RESTORE to `true` within the same run.

## Assertions
- A1 (baseline): `l3_dump_state.notificationSound == true` before any tap.
- A2 (flip): after Step 3, `l3_dump_state.notificationSound == false` — reflects `_setNotificationSoundEnabled`'s `Prefs.setNotificationSoundEnabled(value, toxId)` write (`global_settings_section.dart:90`).
- A3 (restore, final): after Step 5, `l3_dump_state.notificationSound == true` — the gate's terminal `state{equals:true}`; self-cleans ON SUCCESSFUL COMPLETION only (no `teardown` phase — a mid-run failure/interruption can leave the setting flipped; re-run or restore manually).
- A4 (negative, optional under live marionette): `official.get_runtime_errors({})` empty vs Step-1 baseline.

## Notes
- L3-pin reason: real-tap mechanism unproven; L1 promotion gated on validating the marionette `tap` ext. Key verified wired at `lib/ui/settings/global_settings_section.dart:492` (`key: UiKeys.settingsNotificationSoundSwitch`).
- Sibling distinction: **S86** is the DATA half (`l3_set_setting` round-trip, proven); S97 is the REAL-tap of the same switch — same `Prefs` key, different driver layer.
- `notificationSound` is account-scoped Prefs read by the badge/notification path; no DHT or peer involvement → hermetic once the tap works.
- Below-the-fold gotcha: the row lives in the Global Settings card, likely below the fold; the scroll-less JSON runner may not reach it even with a working marionette binding.
- Mobile parity: the notification-sound Switch lives in `lib/ui/settings/global_settings_section.dart:492` (toxee-owned, shared across platforms) → covers mobile.
