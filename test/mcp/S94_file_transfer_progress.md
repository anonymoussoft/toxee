# S94 — File transfer progress (send + receive, 0 → 100)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired, both online) history=empty` (the `paired_for_e2e` snapshot) + a LARGE staged file
**Harness mode**: peerHarness=none (a second live toxee must originate/receive the transfer so intermediate progress chunks actually flow over the DHT — see Notes)
**Promotion target**: L3-pinned because intermediate progress (0<p<100) only manifests when a real DHT transfer chunks a large file between two live toxees; a single process never emits mid-transfer `progress_*` events. Covers feature **G2** (文件进度（收发）, the `progressUpdates` stream). Sibling of S21/S24 (which assert the file ARRIVES) and S88 (image classification); S94 asserts the PROGRESS of the transfer, not just its terminal state.
**Status**: NEEDS-SMALL-TOOL / L3-MANUAL. The progress STREAM exists and is live in-process, but `l3_dump_state` does NOT expose any per-message progress field today — so a runner cannot observe 0→100 yet. Driveable in principle (large file over `paired_for_e2e`), blocked from a gate only by one missing dump field (see Assertions A2 + Notes for the exact field). No executable `run_*.sh` ships for this scenario.

## Precondition
- `paired_for_e2e` restored: A and B in separate Containers, already friends, both online (same base S21/S88 use).
- A LARGE staged file on A — big enough to span multiple `progress_send`/`progress_recv` chunks so at least one intermediate (0<received<total) emission occurs. Tiny files complete in one chunk and skip straight to 100% (no observable intermediate). Pick a size comfortably above the per-transfer chunk + the 200ms throttle window so ≥2 emissions land.
- The file must be ABOVE the receiver's image auto-accept cap consideration but acceptance still happens (non-image generic file auto-accepted under the size limit, or large-file auto-accept via `FakeMessageProvider`'s P1-5 listener — see S24 `S24_accept_incoming_file.md:24`).
- `MCP_BINDING=marionette`; two VM service URIs.

## Driver
1. Connect A + B; `ensureReady` both; `waitForConnected`; `waitForFriendOnline` both ways; resolve `toxA`/`toxB` (same preamble as `drive_fixture_c_file.dart:62-85`).
2. A: send the large file — `l3_send_file(userId: toxB, filePath: <large file>)` (or `content` if synthesizable at size; `l3_debug_tools.dart:1913-1917`).
3. **(BLOCKED on a new field)** On A (send side) AND B (receive side), poll `l3_dump_state.messages[]` for the transfer's progress, expecting it to climb monotonically 0 → 100 before the message finalizes. This step cannot run today — `messages[]` exposes `mediaKind/fileName/filePath/fileSize` only, no progress (`l3_debug_tools.dart:3036-3039`).
4. Terminal: B's row reaches a non-empty `filePath` (transfer done) — this part IS assertable today via the S24 path (`drive_fixture_c_file.dart:285-316`).

## Assertions
- A1 (terminal, assertable today): A surfaces an `isSelf` file message; B surfaces a non-self file message with a non-empty `filePath` (the file completed + was written) — exactly the S21/S24 terminal assertions, which DO have a live gate (`run_fixture_c_file.sh`).
- A2 (progress, BLOCKED — needs a new dump field, headline): a runner can observe `received/total` (or a 0–100 `transferProgress`) climbing for the in-flight transfer on BOTH sides. The data EXISTS in `FfiChatService.progressUpdates` — a broadcast stream of `({instanceId, peerId, path, received, total, isSend, msgID})` (`ffi_chat_service.dart:610-629`), fed by `progress_send:`/`progress_recv:` poll events (`ffi_chat_service.dart:1786-1845` recv; the send branch mirrors it) and throttled to one emission per 200ms per transfer (`_progressThrottleMs`, `ffi_chat_service.dart:632-633`). It is simply not surfaced through `l3_dump_state`.
- A3 (monotonic, BLOCKED): progress never decreases for a given `msgID` (the receive handler overwrites `(received, total)` forward per chunk, `ffi_chat_service.dart:1816-1823`).
- A4: `official.get_runtime_errors({})` baseline-clean both sides; no idle-timeout cleanup mid-transfer (`_fileTransferIdleTimeout` 180s, `ffi_chat_service.dart:644`).

## Notes
- EXACT missing field to make this runner-assertable: add `messages[].transferProgress` (a 0–100 int, or a `{received,total}` pair) to the `l3_dump_state` message map (`l3_debug_tools.dart:3025-3046`). Source it by correlating the message's `msgID`/`filePath` against `FfiChatService._fileReceiveProgress` (recv side) and the send-side progress map (the `progressUpdates` stream already carries `msgID`, `received`, `total`, `isSend` — the dump just needs to read the latest value per msgID). That single field flips S94 from L3-manual to a `drive_fixture_c_progress.dart` gate over the existing large-file transport.
- Why a small file won't do: a transfer that fits one chunk emits only the final 100% (or completes before any throttled emission). The fixture MUST stage a file large enough to force ≥2 throttled emissions (200ms apart) so an intermediate value is observable.
- The progress STREAM is also consumed by the UIKit message bubble (the in-flight progress indicator), but that render is not exposed to MCP either — no `messageItem_<msgId>` ValueKey (same gap S21/S88 record). So even the visual progress bar is screenshot-only.
- Echo peer is NOT a substitute (§3.7): echoes c2c TEXT, cannot originate/receive a file transfer — so it can never produce `progress_*` events.
- Until the field lands, S94 is honestly NOT covered by any gate; the closest live assurance is `run_fixture_c_file.sh` proving the transfer COMPLETES (A1), which says nothing about the 0→100 curve (A2/A3).
