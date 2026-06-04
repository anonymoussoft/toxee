# S85 — Bootstrap node mode switch (auto / manual / lan)

**Layer**: L3 (executable hermetic runner gate)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online`
**Harness mode**: single-instance L3 runner (no echo peer required — the setting is local Prefs state)
**Runner gate**: `tool/mcp_test/scenarios/l3_bootstrap_mode_toggle.json` via `dart run tool/mcp_test/run_l3_scenarios.dart` (hard gate, hermetic)
**Promotion target**: L2 candidate. The settings Bootstrap section now exposes keyed mode controls (`settings_bootstrap_mode_manual|auto|lan`), while the existing runner still covers the underlying Prefs contract (`bootstrapNodeMode`).
**Status**: covered (executable, **setting** half). The **network** half (auto-fetched nodes vs manual node vs LAN actually changing DHT connectivity) is the live-bootstrap leg of S82 and out of scope here. Maps to feature **C1** (节点模式切换 auto/manual/lan, `Prefs.bootstrapNodeMode`, inventory §C.1).

## Precondition
- Account A signed in; `Prefs.getBootstrapNodeMode()` at its default `auto` (`lib/util/prefs.dart:567`). The gate's first step is a `state_contains bootstrapNodeMode "auto"` precondition that fails loudly on a dirty fixture.
- App launched with the L3 surface (`--dart-define=TOXEE_L3_TEST=true`).
- **Mobile caveat**: `lan` is rejected on Android/iOS by the product; this gate toggles `auto↔manual` only, which is valid on every platform.

## Driver
UI-first path: open Settings → Bootstrap section and tap the keyed controls
`settings_bootstrap_mode_manual|auto|lan`.

Runner sibling (current hard gate):
1. `wait_for state_contains bootstrapNodeMode "auto"` — confirm the seeded default.
2. `set_setting { key: "bootstrapNodeMode", value: "manual" }` → `l3_set_setting` typed-enum branch → `Prefs.setBootstrapNodeMode("manual")` (`lib/util/prefs.dart:573`).
3. `wait_for state_contains bootstrapNodeMode "manual"` — the switch took effect.
4. `set_setting { key: "bootstrapNodeMode", value: "auto" }` → restore the default.

## Assertions
- A1 (mid-state, in-step): after Step 2, `l3_dump_state.bootstrapNodeMode == "manual"` (Step 3 `wait_for` throws otherwise).
- A2 (restore, final): after Step 4, `state{field:bootstrapNodeMode, equals:"auto"}` — the fixture self-cleans.
- A3 (enum guard, negative — covered by the tool, not this gate): `l3_set_setting` rejects any `bootstrapNodeMode` value outside `{auto, manual, lan}` with `error:bad_value`.

## Notes
- `bootstrapNodeMode` is a **global** Prefs key (not account-scoped), so the gate restores `auto` at the end to avoid leaking a non-default mode into later scenarios.
- This asserts the **setting** round-trip only. Whether `manual`/`lan` actually re-points the DHT (node fetch suppression, LAN service start) is the network behavior tracked by S82 (custom bootstrap node) and the LAN spec S92 — both need a live network leg the hermetic runner deliberately avoids.
- The settings UI itself (the Bootstrap section segment + connectivity "test" button) is the L9/S90 surface; this gate covers the Prefs contract beneath it.
- UI anchor note: the desktop Bootstrap section now exposes `UiKeys.settingsBootstrapModeManual`, `UiKeys.settingsBootstrapModeAuto`, and `UiKeys.settingsBootstrapModeLan` on the three `RadioListTile`s, so a future UI-first driver no longer needs label-only targeting.
