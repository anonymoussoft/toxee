# S86 — Notification sound toggle (per account)

**Layer**: L3 (executable hermetic runner gate)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online`
**Harness mode**: single-instance L3 runner (no echo peer required)
**Runner gate**: `tool/mcp_test/scenarios/l3_notification_sound_toggle.json` via `dart run tool/mcp_test/run_l3_scenarios.dart` (hard gate, hermetic)
**Promotion target**: L2 candidate. The settings global section now exposes `UiKeys.settingsNotificationSoundSwitch`, while the runner still covers the underlying account-scoped Prefs setting (`notificationSound`).
**Status**: covered (executable, **setting** half). The **effect** half (an inbound message actually playing / suppressing the OS notification sound) needs `log stream` / OS audio capture and is out of scope. Maps to feature **L7** (通知音开关（按账户）, `Prefs.notificationSoundEnabled`, inventory §L.7 — the auto-accept half is S46/S47).

## Precondition
- Account A signed in; `Prefs.getNotificationSoundEnabled()` at its default `true` (account-scoped, `lib/util/prefs.dart:746`). The gate's first step is a `state_contains notificationSound "true"` precondition that fails loudly on a dirty fixture.
- App launched with the L3 surface (`--dart-define=TOXEE_L3_TEST=true`).

## Driver
UI-first path: open Settings → Global settings and toggle
`settings_notification_sound_switch`.

Runner sibling (current hard gate):
1. `wait_for state_contains notificationSound "true"` — confirm the seeded default.
2. `set_setting { key: "notificationSound", value: false }` → `l3_set_setting` bool branch → `Prefs.setNotificationSoundEnabled(false)` for the current account (`lib/util/prefs.dart:763`).
3. `wait_for state_contains notificationSound "false"` — the toggle took effect.
4. `set_setting { key: "notificationSound", value: true }` → restore the default.

## Assertions
- A1 (mid-state, in-step): after Step 2, `l3_dump_state.notificationSound == false` (Step 3 `wait_for` throws otherwise).
- A2 (restore, final): after Step 4, `state{field:notificationSound, equals:true}` — the fixture self-cleans.
- A3 (account scope): the read/write use the no-arg getter/setter, which resolve to the **current** account's scoped key (`acct_notification_sound`), so a second account's value is unaffected (isolation is S72's concern; this gate just proves the per-account write round-trips).

## Notes
- `notificationSound` is **account-scoped**, unlike the global `bootstrapNodeMode`/`autoDownloadSizeLimit` keys — restoring `true` at the end keeps the seeded account clean.
- This is the toggle's **persistence** contract. The downstream consumer (`badge_service` / `notification_service` deciding whether to play a sound) is the K1/K2 surface; verifying the actual OS banner sound is an irreducible OS-audio gate (sibling of the S53/S83 OS-banner halves).
- UI anchor note: the visible per-account switch is now directly targetable by `settings_notification_sound_switch`; a future UI-first driver can toggle the real control before asserting the same Prefs state.
