# S13 — Resend a failed / queued outbound message

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=toggle(online→offline→online) friends=1 history=seeded`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L3-pinned — proving the resend lands needs live DHT delivery against a real peer; an L2 stub can flip `isPending`/`SEND_FAIL` but can't prove network arrival.
**Status**: covered (two retry paths — V1 auto-drain, V2 tap-to-resend)

## Precondition
- Account A plaintext; friend F == echo peer, paired + reachable on the DHT (`bash tool/mcp_test/ensure_echo_peer.sh`; read 76-char `peer_id` from `tool/mcp_test/echo_peer.json`).
- DHT warmup: poll-for-peer-Online loop, not a fixed sleep (5-30s).
- Per-account queue file `<accountDataRoot>/offline_message_queue.json` from `app_paths.dart:332` (`getAccountOfflineQueueFilePath`), injected as `queueFilePath` at `account_service.dart:236-237`. (Default app-support fallback lives at `offline_message_queue_persistence.dart:50` — NOT the per-account path.)
- Failed-msg key `tencent_cloud_chat_failed_messages_<fullToxIdOfA>` in SharedPreferences (`tim2tox_failed_message_persistence.dart:17,29-32`; legacy 16-char prefix auto-migrated `:47-64`).
- Sudo warmed (`sudo -v`) for `ifconfig en0 down/up`. `MCP_BINDING=marionette`.

## Driver — V1 (offline queue auto-resend)
1. Open conversation with F (snapshot → tap row).
2. `sudo ifconfig en0 down`; poll log for `Notified self offline status` (≤10s). Peer stays up.
3. `fmt_enter_text` on chat input (`UiKeys.chatInputTextField`); send via real OS Return (`osascript … key code 36` — synthetic Enter misses UIKit's `RawKeyEvent`).
4. `sudo ifconfig en0 up`; poll log ≤120s for self-online → friend-online → `_sendPendingMessages` → `_drainTextItem`.

## Driver — V2 (SEND_FAIL tap-to-resend)
5. Force a `sendMessage` exception so the bubble flips `SEND_FAIL` (`tim2tox_sdk_platform.dart:5508`/outer-catch `:5571`); if the disconnect race is hard by hand, drive via `fmt_evaluate_dart_expression` against an invalid receiver.
6. Snapshot → confirm failed bubble exposes the `Retry` Semantics node (`tencent_cloud_chat_message_item.dart:134-137`).
7. Bring F online; `marionette.tap` the refresh glyph (one-tap retry `:169-171`); fallback `marionette.long_press` → confirm dialog (`resendTips`, en) `:104` → `Confirm`.
8. Poll log for `reSendMessage` (`tim2tox_sdk_platform.dart:5877`) → echo arrival.

## Assertions
- A1 (V1): post-down — `Notified self offline status` in log.
- A2 (V1): pending bubble visible; `jq '.["<F_id>"] | length' offline_message_queue.json` → `1`.
- A3 (V1): post-up — log has `_sendPendingMessages` for F + `_drainTextItem` (`ffi_chat_service.dart:6576,6635`); bubble flips pending→delivered; `jq` count → `0`.
- A4 (V1, echo): sent text appears a second time, verbatim (`echo_peer.cpp:85`).
- A5 (V2): failed bubble exposes `Retry` node; failed-msg key has an entry for F.
- A6 (V2): after resend — `reSendMessage` in log, exactly ONE bubble (pre-resend `deleteMessages([msgID])` `:6099`); failed entry removed (`removeFailedMessage` `:6118`).
- A7 (V2, echo): resent text echoed back verbatim.
- A8: `official.get_runtime_errors({})` empty vs Step-1 baseline.
- Negative grep (no stable success log exists — assert on these FAILURE strings being ABSENT): `_sendPendingMessages: friend <F>… went offline mid-drain` (`ffi_chat_service.dart:6616`), `_sendPendingMessages: drain failed for text item` (`:6620`), `reSendMessage: failed message not found for msgID=` (`tim2tox_sdk_platform.dart:5945`), `reSendMessage exception:` (`:6132`).

## Notes
- V1 (pending/`SENDING`) has NO resend affordance; the refresh glyph is SEND_FAIL-gated only (`tencent_cloud_chat_message_item.dart:170,190`).
- A pending bubble force-failed (SIGKILL/`loadHistory`) flips `isPending:false` → converter maps to `SEND_SUCC`, not `SEND_FAIL` (`tim2tox_sdk_platform_converters.dart:295-304`) — so it does NOT surface the glyph. Main correctness trap.
- Tear-down: `kill $SUDO_KEEPALIVE_PID 2>/dev/null; sudo ifconfig en0 up` on EXIT.
- Wanted UiKeys (absent in lib/): `message_list_item:<msgID>`, `message_resend_button:<msgID>`.
