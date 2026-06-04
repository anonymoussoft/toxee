# S87 — Download directory + auto-download size threshold

**Layer**: L3 (executable hermetic runner gate)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online platform=desktop`
**Harness mode**: single-instance L3 runner (no echo peer required)
**Runner gate**: `tool/mcp_test/scenarios/l3_download_limit_toggle.json` via `dart run tool/mcp_test/run_l3_scenarios.dart` (hard gate, hermetic)
**Promotion target**: L2 candidate. The settings global section now exposes `UiKeys.settingsDownloadLimitField` and `UiKeys.settingsDownloadLimitSaveButton`, while the current runner still drives the Prefs setting (`autoDownloadSizeLimit`) directly.
**Status**: covered (executable, **threshold** half). The download-**directory** half is surfaced read-only in `l3_dump_state.downloadsDirectory` but not toggled here (it is a native folder picker, sibling of the S79 avatar picker). Maps to feature **L8** (下载目录设置 + 自动下载阈值, `Prefs.autoDownloadSizeLimit` / `downloadsDirectory`, inventory §L.8 + §G.1).

## Precondition
- Account A signed in; `Prefs.getAutoDownloadSizeLimit()` at its desktop default `30` MB (`lib/util/prefs.dart:838`; mobile default is 5 MB — this gate runs on the macOS L3 host so the baseline is 30). The gate's first step is a `state_contains autoDownloadSizeLimit "30"` precondition that fails loudly on a dirty fixture.
- App launched with the L3 surface (`--dart-define=TOXEE_L3_TEST=true`).

## Driver
UI-first path: open Settings → Global settings, type into
`settings_download_limit_field`, and tap
`settings_download_limit_save_button`.

Runner sibling (current hard gate):
1. `wait_for state_contains autoDownloadSizeLimit "30"` — confirm the desktop seeded default.
2. `set_setting { key: "autoDownloadSizeLimit", value: 13 }` → `l3_set_setting` typed-int branch → `Prefs.setAutoDownloadSizeLimit(13)` (`lib/util/prefs.dart:843`).
3. `wait_for state_contains autoDownloadSizeLimit "13"` — the new cap took effect.
4. `set_setting { key: "autoDownloadSizeLimit", value: 30 }` → restore the desktop default.

## Assertions
- A1 (mid-state, in-step): after Step 2, `l3_dump_state.autoDownloadSizeLimit == 13` (Step 3 `wait_for` throws otherwise).
- A2 (restore, final): after Step 4, `state{field:autoDownloadSizeLimit, equals:30}` — the fixture self-cleans.
- A3 (type guard, covered by the tool): `l3_set_setting` rejects a non-int / negative `autoDownloadSizeLimit` value with `error:bad_value`.
- A4 (directory read, no-op here): `l3_dump_state.downloadsDirectory` is present (null when unset → the platform default download dir is used by `FfiChatService` auto-download); a future native-picker gate (sibling S79) can drive the directory write.

## Notes
- `autoDownloadSizeLimit` is a **global** int (MB) consumed by the file auto-accept / auto-download path (`Prefs.autoDownloadSizeLimit`, inventory §G.1); the gate restores `30` at the end to avoid leaking a non-default cap.
- The threshold is the gate that decides whether an inbound file is auto-downloaded (S24 accept-file is the receive-side behavior). This spec asserts the **setting** round-trip, not the size-boundary auto-accept decision — that boundary behavior is a follow-up two-process extension of `run_fixture_c_file.sh` (send a file just under vs just over the cap).
- UI anchor note: a future UI-first driver can type into `settings_download_limit_field` and tap `settings_download_limit_save_button` before asserting the same persisted threshold.
