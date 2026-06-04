# Product-screenshot pipeline

One command produces the product screenshots for every main feature, using
four REAL toxee instances with persistent, reusable seed data (accounts,
friendships, a group, rich conversations). Output lands in `./screenshot/`.

```bash
./tool/screenshots/capture.sh                 # reuse seed (fast) or first-run seed
./tool/screenshots/capture.sh --build         # (re)build the L3-enabled debug app first
./tool/screenshots/capture.sh --reset         # surgical seed rebuild from scratch
./tool/screenshots/capture.sh --sync-site     # + downscale curated copies to doc/product/assets/
./tool/screenshots/capture.sh --p0-only       # only the 8 must-have scenes
./tool/screenshots/capture.sh --include-incall  # also the in-call scene (may hit mic TCC prompt)
```

**While it runs, don't touch mouse/keyboard** — the scene walk owns window
focus (same constraint as the real-UI test harness).

Plan + design rationale:
`docs/plans/2026-06-03-product-screenshots-and-landing-page.md`.

## What it does

1. **Launch** `ShotA` (hero, "Mia") + `ShotB/C/D` partners via
   `tool/mcp_test/launch_toxee_instance.sh`, with
   `TOXEE_MULTI_RUNTIME_ROOT` + `TOXEE_INSTANCE_APP_SUPPORT_DIR` pointed at
   the self-contained seed root `tool/screenshots/_seed_runtime/`
   (gitignored). First run registers the personas via `l3_register_account`
   (any nickname — the persistent seed-account marker authorizes the l3
   tools); later runs auto-login and REUSE everything.
2. **Doctor** the manifest (`_seed_runtime/seed_manifest.json`) against live
   state. "Manifest present but account not restored" means something
   external wiped the shared defaults (the fixture-C harness clears the whole
   `com.toxee.app` domain) → exit 2, re-run with `--reset`.
3. **Seed (idempotent)** friendships A↔B/C/D, the private NGC group
   `Weekend Hikers 🏔` (invite + auto-accept; full-mesh loopback DHT), and
   the scripted conversations — inbound photo (image bubble), `Trip-Plan.pdf`
   (file bubble), a sender-side quoted reply, emoji, group chatter, pinned
   group, muted contact.
4. **Freshen** every run BEFORE any conversation opens: ShotB/C/D send new
   lines so timestamps read "just now" and ShotC/D carry unread badges
   through the whole scene walk (their conversations are never opened).
5. **Scene walk** on the hero instance — real tabs, real tiles, real
   overlays — capturing via `flutter_skill.screenshot` (window must be
   foreground; actual PNG size is measured and logged, not assumed).

## Scenes

| P0 (hard-fail) | P1 (warn-only) | P2 (flag) |
|---|---|---|
| 01 conversations (master-detail, badges/pin/mute) | 09 incoming call (ringing) | 15 in-call (`--include-incall`) |
| 02 hero chat (photo/reply/emoji) | 10 outgoing call (ringing) | |
| 03 group chat | 11 zh locale | |
| 04 contacts | 12 message search | |
| 05 profile + Tox ID QR | 13 Applications/IRC | |
| 06 settings | | |
| 07/08 dark list + dark chat | | |

Call shots are taken in the RINGING state on both sides: the AV service is
already initialized at session boot, but mic capture only starts on accept —
so no TCC prompt is involved (the in-call scene is opt-in for that reason).

## Maintenance notes

- The app must be built with the L3 surface compiled in
  (`MCP_BINDING=skill` + `TOXEE_L3_TEST=true` dart-defines). `--build` does
  this via `TOXEE_BUILD_ONLY=1 ./run_toxee.sh`.
- Partner instances run from per-instance `.app` copies under
  `_seed_runtime/app_copies/`, refreshed by executable-mtime comparison
  (stale-dylib gotcha).
- `--reset` is SURGICAL: seed root + container `multi_instance/Shot*`
  leftovers + only the `toxee_shot*.`-prefixed `com.toxee.app` defaults keys.
  It never runs `defaults delete com.toxee.app`.
- Generated media (procedural lake photo PNG + a tiny valid PDF) is cached
  under `_seed_runtime/generated_media/`.
- The product page consumes the curated copies in `doc/product/assets/`
  (committed); refresh them with `--sync-site`.
