# Fixture C Multi-instance Spike Harness

This directory now contains a **minimal runnable skeleton** for the
`doc/research/MULTI_INSTANCE_SPIKE.en.md` sequence:

- `launch_toxee_instance.sh <name>`: launch one debug `Toxee.app`
  directly, capture stdio, derive the VM service URI, and record a
  safe-to-teardown process triple.
- `stop_toxee_instance.sh <name>`: stop one recorded instance without
  signaling unrelated `Toxee` processes.
- `launch_fixture_c_pair.sh`: launch instance `A` and `B`, then write
  `tool/mcp_test/.multi_instance_runtime/pair.json`.
- `stop_fixture_c_pair.sh`: stop `B`, stop `A`, then report whether
  `pgrep -fl "Debug/Toxee.app"` is empty.
- `probe_vm_service.dart`: attach-level readiness probe (`getVM()` only).
- `drive_fixture_c_pair.dart`: disposable non-media end-to-end driver
  (register A/B or boot restored A/B, add friend when needed, ping, pong).
- `restore_fixture_c_pair.sh`: restore the reusable `paired_for_e2e`
  A/B fixture into the per-instance App Support roots.
- `run_fixture_c_non_media.sh [fresh|paired_for_e2e]`: executable wrapper
  for the S61/S62 non-media two-process gates.

## Why direct-binary launch?

`run_toxee.sh` is still the canonical single-instance developer launcher,
but for the spike it has two constraints:

1. it writes `build/vm_service_uri.txt` and stdio logs to shared paths;
2. it fronts the app with a wrapper shell, which makes per-instance
   bookkeeping noisier.

The spike harness instead launches the already-built app binary
`build/macos/Build/Products/Debug/Toxee.app/Contents/MacOS/Toxee`
directly and records its own per-instance runtime tree under:

`tool/mcp_test/.multi_instance_runtime/<A|B>/`

For the current build, `launch_fixture_c_pair.sh` launches:

- `A` from the original `Toxee.app`
- `B` from a fresh physical copy `app_copies/ToxeeB.app`

because launching both from the exact same `.app` path left the
direct-launch VM attach path unhealthy. The copied bundle is disposable
and recreated on every pair launch.

`TOXEE_MULTI_LAUNCH_METHOD=open` remains available for LaunchServices
experiments, but on 2026-06-01 it attached successfully while leaving the
paired DHT route unreliable. The default is therefore `direct`.

## What is already automated?

Today:

1. launch A
2. launch B
3. confirm A/B have distinct PIDs
4. confirm A/B have distinct VM service URIs
5. route each instance through its own
   `TOXEE_APP_SUPPORT_DIR=~/Library/Containers/com.toxee.app/.../multi_instance/<A|B>`
   subtree so logs / account_data / profiles stop colliding
6. probe VM attachability on both instances
7. drive fresh register A / register B / add friend / accept / ping / pong
8. restore `paired_for_e2e`, boot both existing accounts, and ping / pong
9. teardown A/B using recorded pid+start_time+cmdline triples

Still manual / future work:

1. layer more non-media two-process scenarios on top of `paired_for_e2e`
2. decide whether a second bundle id is needed beyond the current
   SharedPreferences prefix + per-instance App Support isolation
3. layer media / call scenarios on top

## Current findings

After local runs on 2026-05-30 and 2026-06-01:

1. A and B launch concurrently and get different VM service URIs.
2. A plain `HOME` override is **not** enough by itself, but the new
   `TOXEE_APP_SUPPORT_DIR` seam can isolate the in-app App Support root
   under `.../multi_instance/A|B`.
3. Launching B from a copied bundle path (`app_copies/ToxeeB.app`) plus
   probing A before/after B launch stabilizes the attach path.
4. `TOXEE_SHARED_PREFS_PREFIX` is now recorded in `instance.json` and exposed
   by `l3_dump_state`, with A/B showing `toxee_a.` and `toxee_b.`.
5. `drive_fixture_c_pair.dart` now completes the fresh non-media sequence:
   register A, register B, friend request B->A, accept on A, ping, pong.
6. `paired_for_e2e` restore boots the saved A/B accounts and completes
   ping/pong without re-registering or re-friending.

That means this harness is no longer just launch/teardown scaffolding —
it now proves the non-media chat/friendship slice of Fixture C and provides a
reusable paired base for later two-process scenarios.

## Quick start

```bash
cd /Users/bin.gao/chat-uikit/toxee
tool/mcp_test/launch_fixture_c_pair.sh
cat tool/mcp_test/.multi_instance_runtime/pair.json
tool/mcp_test/stop_fixture_c_pair.sh
```

Run the executable non-media gates:

```bash
tool/mcp_test/run_fixture_c_non_media.sh paired_for_e2e
tool/mcp_test/run_fixture_c_non_media.sh fresh
```

If the app is not built yet, build it first with the usual debug path:

```bash
MCP_BINDING=marionette ./run_toxee.sh
```

Then quit the app and run the pair launcher.
