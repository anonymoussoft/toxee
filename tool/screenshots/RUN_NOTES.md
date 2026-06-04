# Product-screenshot pipeline — run notes & findings

What the build-out surfaced while driving the real app across 4 instances.
These are recorded for follow-up; the screenshot tool works around each.

## App bugs found (real, product-affecting)

1. **Binary-replacement path persisted protocol customs as chat bubbles.**
   Delivery/read **receipts** (and reactions/typing) arrived on the
   binary-replacement path wrapped as V2TIM custom messages and were saved to
   history, so chats rendered raw `{"type":"receipt",...}` JSON bubbles and
   conversation previews showed them as "last message". **Fixed** in
   `binary_replacement_history_hook.dart` (`_isInternalProtocolCustom` drops
   receipt/reaction/typing at `saveMessage`; `av_call` deliberately kept — it
   is the call-record row). Shared Dart → covers mobile. *This is a genuine
   fix, not screenshot-only.*

2. **`l3_create_group` left the group titled by its raw local id.**
   The UI create path stores the display name in `Prefs.setGroupName`; the L3
   create tool didn't, so conversation tiles/headers showed `tox_1`. **Fixed**
   (l3_create_group now persists the name). Shared Dart → mobile covered.

3. **`l3_send_file content` corrupts binary (PNG/PDF).** Pre-existing: the
   `content` arg uses `writeAsString`. Added a binary-safe `contentB64` source
   path rather than changing `content`'s contract. Shared Dart.

## App issues OBSERVED but worked around (follow-up owed)

4. **Cmd+Ctrl+F search shortcut is unreachable on macOS.** `home_page.dart`
   binds search to `SingleActivator(keyF, meta:true, control:true)`; macOS
   eats Cmd+Ctrl+F as the system fullscreen shortcut, so Flutter never sees
   it. The pipeline drives search via the visible header "Search" box
   instead. *Fix candidate: rebind to Cmd+F (meta-only).*

5. **Same-host NGC group peer links don't reliably establish.** Even with
   full-mesh loopback bootstrap, members joined the group (announce lookup ok)
   but the per-pair peer connection was a coin flip — one member connected,
   another never did across 3 min of S37-style message nudging. C2C is
   reliable; group transport on a single host is not. The pipeline seeds the
   group's multi-sender history through `l3_inject_group_text` (the real
   ingestion seam) on the hero instance. *Not a screenshot bug per se, but the
   same fragility the S37 notes flagged — worth a protocol-layer look.*

6. **First call of a session can race TUICallKitAdapter lazy init.** The
   first `l3_start_call` sometimes returned without the callee reaching
   `ringing` (adapter "Service initialized" landed in the same second). The
   scene retries once after a warm-up. Also: an instance that completed a call
   refuses new calls ("adapter returned false") until restarted — capture.sh
   restarts ShotB between the seed and scene phases.

7. **Live-session vs persisted conversation-list drift.** Right after
   seeding, the hero's live conversation list showed sender-side raw-key ghost
   rows and live-path `[Custom]` bubbles that are NOT in persisted history.
   A fresh boot renders the correct persisted truth — so capture.sh restarts
   ShotA between the seed and scene phases. *The normalization gap between the
   live emit and the persisted record is worth a separate investigation.*

## Harness gotchas (environmental, not app bugs)

- **App-support can't live under the repo seed root.** The sandboxed app gets
  EPERM creating `…/profiles` under a repo path, so app-support stays at the
  launcher default (the macOS container `multi_instance/<inst>/`); `--reset`
  cleans both. Only `HOME`/runtime live under the seed root.
- **VM-service websocket drops mid-run** under load (macOS backgrounded-window
  throttling suspected) while the app stays healthy — the driver reconnects to
  the recorded ws URI and re-resolves the isolate.
- **Modal barrier swallows keyed taps.** Tapping a sidebar tab while the
  profile dialog is up reports `success` but only reaches the barrier; the
  scene order opens the profile modal LAST and the shooter has a
  byte-identical-frame guard that fails loudly if navigation silently no-ops.
- **macOS bash 3.2**: `"${arr[@]}"` on an empty array trips `set -u`; use the
  `${arr[@]+"${arr[@]}"}` guard.
