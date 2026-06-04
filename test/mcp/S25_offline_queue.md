# S25 — Offline queue → reconnect → deliver

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=toggle(online→offline→online) friends=1(reachable on DHT)`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L3-pinned forever — flow requires hard-killing the network (`sudo ifconfig en0 down/up`), force-killing the Toxee binary, real Tox DHT bootstrap on both ends. This is the primary regression gate for the offline-first claim.
**Status**: covered

## Precondition
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` — idempotent; on first call, builds + launches the bot if needed; waits for ID emission. Reads `tool/mcp_test/echo_peer.json` to capture `peer_id` (76-char Tox address). Bot auto-accepts friend requests + echoes received c2c text verbatim.
- **DHT warmup**: scenario runner should wait for `_drive_seed.dart`-style logic to confirm peer is DHT-reachable from the toxee side before proceeding — typically 5-30s; use a poll-for-peer-Online loop, not a fixed sleep.
- **Cleanup**: scenario runner should call `bash tool/mcp_test/stop_echo_peer.sh` in teardown (or rely on session-level reuse if running a batch).
- Account A (plaintext), single friend F paired and reachable on the DHT
- F is online before the test starts (sidebar Online, `getFriendList: <F>… online=true` in log)
- Sudo warmed (`sudo -v`) or passwordless sudoers rule for `ifconfig en0 down/up` — MCP cannot fulfill a TTY prompt
- Queue file path: `<accountDataRoot>/offline_message_queue.json`
- F-side instance running (Fixture C twin recommended) — F must stay reachable through the network flap to deliver on reconnect

## Driver

**Note**: in this scenario, the **echo peer stays ONLINE the entire time** — it's the toxee side (account A) that goes offline via `ifconfig en0 down` and back online via `ifconfig en0 up`. The bot doesn't move. After reconnect, expect the queued messages to be sent + echoed back verbatim by the peer.

1. Open conversation with F (semantic snapshot → tap row); F here is the echo peer whose 76-char ID was loaded into the contact list during fixture setup (read from `tool/mcp_test/echo_peer.json`)
2. Shell: `sudo ifconfig en0 down`. Poll log for `HandleSelfConnectionStatus: Notified self offline status` and `getFriendList: <F>… online=false` (≤10s). The echo peer remains running on its own host — only toxee's network is severed.
3. Send message via marionette input + send button (fallbacks via semantic snapshot — no stable keys yet). Expect immediate pending bubble.
4. Shell: `pkill -KILL -f "Debug/Toxee.app/Contents/MacOS/Toxee"` (hard SIGKILL — proves queue durability)
5. Relaunch toxee (still offline), reconnect MCP, reopen conversation
6. Shell: `sudo ifconfig en0 up`. Poll log up to 120s for self-online → friend-online → `_sendPendingMessages` → `_drainTextItem`. After the drain succeeds, expect each queued message text to appear a **second time** in the conversation panel — the echo peer mirrors verbatim (no `echo:` prefix; see `tool/mcp_test/echo_peer_src/echo_peer.cpp:85`).

## Assertions
- A1: pre-send — A online, F reachable
- A2: post-`ifconfig down` — `Notified self offline status` in log
- A3: outgoing bubble visible in pending state (UIKit pending signal: `customElem.data == '{"isPending":true}'` per `fake_msg_provider_mapping.dart:560-576`)
- A4: queue file contains 1 item under F's normalized ID. `jq '.["<F_id>"] | length' $QUEUE_FILE` → `1`
- A5: queue file survives SIGKILL (re-stat after `pkill -KILL` → still `1`)
- A6: post-relaunch — bubble reappears with same text + pending state; `_loadOfflineQueue` ran
- A7: post-`ifconfig up` — bubble flips to delivered
- A8: queue file drained — `jq` count returns `0` (or key absent)
- A9: log contains `_sendPendingMessages` for F AND does NOT contain `_sendPendingMessages: friend <F>… went offline mid-drain`
- A10: `official.get_runtime_errors({})` empty vs Step 1 baseline
- Negative grep: `_sendPendingMessages: drain failed for text item`, `[OfflineMessageQueuePersistence] saveQueue error`

## Notes
- Tear-down trap: `kill $SUDO_KEEPALIVE_PID 2>/dev/null; sudo ifconfig en0 up` on EXIT so a crash doesn't leave the dev box without network
- Step 8 latency variance is dominated by Tox DHT re-bootstrap (30–120s from cold cache, <60s with LAN-bootstrap twin)
- `MessageHistoryPersistence` per-account injection (via `currentAccountToxId`) is what makes A6 work; if you see the per-account fallback warning in log, fix the fixture, don't relax A6
- Partial key status: the conversation row is now targetable via `conversation_list_item:<friendId>`. The remaining wanted anchors are `chat_message_input_field`, `chat_message_send_button`, `chat_message_item:<msgID>`, and `chat_message_item_pending:<msgID>`.
- Optional tim2tox patch: add `_logger.log('[FfiChatService] _drainTextItem: flipping pending msgID=<...> -> delivered')` after the `copyWith(isPending: false)` for a precise pass marker
