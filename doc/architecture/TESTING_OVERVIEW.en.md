# Testing Overview — toxee

> Language: [Chinese](TESTING_OVERVIEW.md) | [English](TESTING_OVERVIEW.en.md)
>
> The one-stop map of every toxee test asset: what exists, how it is
> classified, the cheapest-to-most-expensive order to run it, and what
> runs in CI versus locally. The authoritative reorganization plan is
> [`doc/research/TEST_CASE_ORGANIZATION_PLAN.en.md`](../research/TEST_CASE_ORGANIZATION_PLAN.en.md);
> this doc is the human/agent-facing summary of its §1, §2, and §3.5.
>
> Scope: **toxee test assets only**. The protocol-layer suite under
> `third_party/tim2tox/auto_tests/` keeps its own phase manifest
> (`run_tests_ordered.sh`) and CI tiers and is referenced here, not
> reorganized.

## 1. Inventory (current reality)

| # | Surface | Where | Count | Runs via | In CI? |
|---|---------|-------|-------|----------|--------|
| 1 | Unit + widget tests (L1) | `test/` (excl. `test/mcp/`) | 122 files (87 tracked, 35 new; ignored junk excluded) | `flutter test` | analyze.yml, every PR |
| 2 | Real-UI WidgetTester gates (L1) | `test/ui/chat_core_real_ui_test.dart` | 6 gates | `flutter test` | analyze.yml |
| 3 | Anchor/key source tests (L1) | `test/ui/testing/`, `test/ui/contact/`, … | 17 files (anchor/key/L3-debug) | `flutter test` | analyze.yml |
| 4 | Host-bundle lifecycle (L2) | `integration_test/` | 6 Dart files (5 runnable `_test.dart` tagged `needs-native` + 1 harness) | per-file `flutter test -d <os>` | e2e.yml, opt-in `ci:e2e` |
| 5 | L3 runner gates (data layer) | `tool/mcp_test/scenarios/*.json` | 46 (40 blocking, 6 nonBlocking) | `run_l3_scenarios.dart` against a live debug app | no (local) |
| 6 | Two-process Fixture C drivers | `tool/mcp_test/drive_fixture_c_*.dart` + `.sh` | 27 Dart drivers / 28 shell wrappers | per-script | no (local); contracts via mcp_harness_smoke.yml |
| 7 | Two-process real-UI driver | `tool/mcp_test/drive_real_ui_pair.dart` | 4 codified scenarios (handshake/handshake_detail/decline/message) | script + osascript | no (local, macOS) |
| 8 | Single-instance UI script driver | `tool/mcp_test/drive_export_account.dart` | 1 | script | no (local) |
| 9 | Harness self-checks | `fixture_c_helpers_regression.sh`, `echo_peer_{contract_smoke,drift_check,helpers_regression}.sh` | 4 scripts | per-script | fixture-c one in mcp_harness_smoke.yml; echo ones local |
| 10 | L3 playbooks (specs) | `test/mcp/S*.md` | 118 (S1–S125, gaps) | agent-driven | n/a (specs) |
| 11 | Protocol tiers (out of scope) | `third_party/tim2tox/auto_tests` | 14 phases | `run_tests_ordered.sh` | auto_tests*.yml tiers 1–4 |

## 2. Canonical taxonomy: two orthogonal axes

Every executable test asset is placed on **two** independent axes. Do not
collapse them — a test's dependency layer and its execution cost are
different questions.

### Axis 1 — dependency layer (L1 / L2 / L3)

The existing, authoritative model lives in
[`doc/architecture/UI_TEST_LAYERING.en.md`](UI_TEST_LAYERING.en.md):
**the lowest layer that can express the test wins.**

- **L1** — pure Dart + mocked channels + a constructor seam. `test/`.
- **L2** — real Hive bootstrap, real `libtim2tox_ffi`, real
  `path_provider`, but **no** live network. `integration_test/`
  (tag `needs-native`).
- **L3** — live Tox DHT, two toxee processes, native file picker,
  microphone/camera permission. The MCP/L3 harness under
  `tool/mcp_test/`.

### Axis 2 — execution class (machine-readable)

Axis 2 is what the reorganization plan adds: exactly **one** execution
class per executable artifact, derived from declared flags rather than
hand-maintained in a central table.

| Class | Meaning | Today's members |
|-------|---------|-----------------|
| `ci-hermetic` | `flutter test`, no native lib, every PR | all of `test/` incl. real-UI WidgetTester + anchor tests |
| `ci-host-bundle` | real host binary + `libtim2tox_ffi`, opt-in label | `integration_test/` (6) |
| `harness-contract` | hermetic contract checks of the harness itself; sub-field `ci: true\|false` | `fixture_c_helpers_regression.sh` (ci: true); `echo_peer_contract_smoke.sh`, `echo_peer_drift_check.sh`, `echo_peer_helpers_regression.sh` (ci: false) |
| `l3-gate` | single instance, live app, `l3_*` debug tools, no peer | 35 scenario JSONs |
| `l3-gate-echo` | single instance + echo peer (live DHT) | 7 scenario JSONs (`requiresEchoPeer`) |
| `l3-ui-single` | single instance, drives REAL widgets (marionette/skill taps or script) | 4 `l3_settings_*_tap` JSONs (nonBlocking) + `drive_export_account.dart` + S96–S125 campaign playbooks |
| `2proc-l3` | two toxee processes, driven via `l3_*` tools | all `drive_fixture_c_*` (they use debug tools, not widget driving) |
| `2proc-ui` | two toxee processes, REAL widgets + osascript | `drive_real_ui_pair.dart` only |
| `manual-playbook` | L3-pinned, agent-driven only (OS dialogs, media HW, kill+relaunch) | remaining `S*.md` |

(35 + 7 + 4 = 46 scenario JSONs. Classes are derived from JSON flags, so
these rosters are never hand-counted again.)

Mapping to the commonly-requested categories:

- **CI** = the `ci-*` classes.
- **Single-instance real UI** (单实例 real UI) = `l3-ui-single`, plus the
  real-UI WidgetTester gates (which are real UI *inside* CI).
- **Two-process real UI** (双进程 real UI) = `2proc-ui`.
- The data-layer harness classes (`l3-gate*`, `2proc-l3`) are deliberately
  kept distinct because they bypass widgets on purpose.

A test asset's class is **declared where the asset lives** (a JSON field, a
script header, or a playbook header) and **aggregated by a generator**,
never maintained by hand in a central table again.

## 3. Recommended campaign order (cheap → expensive)

Run the suites in this order; each step is strictly cheaper and faster than
the next, so failures surface at the lowest cost first. Each step exits 0
standalone — the `--class` selector guarantees no spurious SKIP-exit-2 from
the partitions you did not select.

| # | Step | Class | Entry command |
|---|------|-------|---------------|
| 1 | Unit + widget | `ci-hermetic` | `flutter test` |
| 2 | Host-bundle lifecycle (if native lib built) | `ci-host-bundle` | `flutter test integration_test/` |
| 3 | L3 hermetic suite | `l3-gate` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-gate` |
| 4 | L3 echo suite | `l3-gate-echo` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-gate-echo --echo` |
| 5 | UI-tap suite (nonBlocking) | `l3-ui-single` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-ui-single --allow-skip` |
| 6 | Fixture C non-media | `2proc-l3` | `bash tool/mcp_test/run_fixture_c_suite.sh --tier=non-media` |
| 7 | Fixture C media | `2proc-l3` | `bash tool/mcp_test/run_fixture_c_suite.sh --tier=media` |
| 8 | Two-process real-UI pair | `2proc-ui` | `dart run tool/mcp_test/drive_real_ui_pair.dart` (+ osascript; macOS) |
| 9 | Manual playbooks | `manual-playbook` | agent-driven, only for what nothing above expresses (`test/mcp/S*.md`) |

Notes:

- `<ws_uri>` is the live debug app's VM-service WebSocket URI ending in
  `/ws` (e.g. `ws://127.0.0.1:8181/abcd=/ws`). Launch the app first; the
  MCP/L3 playbook documents the no-DDS launcher and how to read the URI.
- Steps 3–8 require a **running** desktop debug build; they are not
  hermetic. Steps 1–2 are.
- Step 9 is the catch-all for flows that genuinely cannot be expressed by
  any cheaper class (OS dialogs, real media hardware, kill-and-relaunch).

## 4. CI status per class

| Class | In CI today | Where |
|-------|-------------|-------|
| `ci-hermetic` | **Yes**, every PR | `analyze.yml` (`flutter test`) |
| `ci-host-bundle` | **Opt-in** (label `ci:e2e`) | `e2e.yml` |
| `harness-contract` (ci: true) | **Yes**, hermetic | `mcp_harness_smoke.yml` (`fixture_c_helpers_regression.sh`) |
| `harness-contract` (ci: false) | No (local) | echo-peer contract/drift/regression scripts |
| `l3-gate`, `l3-gate-echo`, `l3-ui-single` | **No** (local gate) | `run_l3_scenarios.dart` against a live app |
| `2proc-l3`, `2proc-ui` | **No** (local, macOS) | Fixture C suite + `drive_real_ui_pair.dart` |
| `manual-playbook` | n/a (specs) | `test/mcp/S*.md` |

Additionally, `mcp_harness_smoke.yml` runs the hermetic harness-validation
steps (scenario-JSON schema/suite validation via the runner's
`--validate-only`, and the generated-index `--check` invariants) so
the harness metadata cannot silently drift even though the live L3 suites
themselves do not run in CI.

**Why the live classes are not in CI yet.** Running the L3 hermetic suite in
CI needs a macOS runner + an app build + a seeded account — unblocked but
expensive. The MCP-automation maturity verdict (2026-06-01) stands: live
L3 / two-process testing is a **local point-in-time gate**, not yet a
trustworthy CI regression gate. The path to promoting it is tracked in
[`doc/research/UI_AUTOMATION_ROADMAP.en.md`](../research/UI_AUTOMATION_ROADMAP.en.md).

## 5. Mobile parity (honest gap)

The taxonomy itself is platform-neutral, and the **L1 widget tests already
cover the mobile input/menu variants** (`..._input_mobile.dart` and the
mobile call/notification surfaces, via the vendored UIKit fork) — shared-Dart
gates run identically on the mobile widget tree.

The honest gap is the **live-instance classes** (`l3-*`, `2proc-*`): they
are **desktop-host-only today**. They drive a real desktop debug build via a
VM-service URI and osascript, none of which exists on a phone. Mobile
runtime automation (driving the real app on iOS/Android, including native
OS dialogs) is a **Patrol / E2E roadmap item**, not covered by the current
L3 harness. See the end-to-end strategy in
[`E2E_TESTING.en.md`](E2E_TESTING.en.md) (Patrol for mobile native dialogs)
and the roadmap in
[`doc/research/UI_AUTOMATION_ROADMAP.en.md`](../research/UI_AUTOMATION_ROADMAP.en.md).

## 6. What to read next

- [`UI_TEST_LAYERING.en.md`](UI_TEST_LAYERING.en.md) — the L1/L2/L3 policy,
  the promotion protocol, and the state vectors. Axis-1 authority.
- [`MCP_UI_TEST_PLAYBOOK.en.md`](MCP_UI_TEST_PLAYBOOK.en.md) — the L3 MCP
  routing matrix, the no-DDS launcher contract (how to get `<ws_uri>`), and
  the L3 scenario catalog.
- [`../../test/mcp/INDEX.en.md`](../../test/mcp/INDEX.en.md) — the
  **generated** coverage index: one row per S-number with layer, execution
  class, executable artifacts, and status (generated by
  `gen_scenario_index.dart`; its freshness is CI-gated by
  `mcp_harness_smoke.yml` via `--check`).
- [`E2E_TESTING.en.md`](E2E_TESTING.en.md) — end-to-end strategy and the
  mobile-native-dialog (Patrol) plan.
- [`doc/research/TEST_CASE_ORGANIZATION_PLAN.en.md`](../research/TEST_CASE_ORGANIZATION_PLAN.en.md)
  — the authoritative reorganization plan this overview summarizes
  (schema, runner ordering, hygiene, migration steps).
