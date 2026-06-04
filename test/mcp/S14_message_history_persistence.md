# S14 — Message history persistence across relaunch

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=any friends=1 history=seeded(N=5)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L2 candidate for the in-process count/text capture half once `message_list_item:<msgID>` keys land; L3-pinned for the kill+relaunch half (needs real disk round-trip)
**Status**: covered (default A+F+hist with N=5)

Sister to `S25_offline_queue.md` (queue durability) and `S12_send_text_message.md` (one step short of the kill). S14 covers the **delivered** history side.

## Precondition
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — restores `~/Library/Containers/com.toxee.app/Data/...` (profiles + account_data) + Prefs (`flutter.account_list`, `flutter.current_account_tox_id`, `flutter.local_friends_<prefix>`, scoped per-account keys) from cached tarball at `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst`. The restore wipes existing toxee state.
- **Seeded state**: after restore, the active account is `echo_seeded_test` (auto-login enabled); 1 friend (the echo peer) is in the contact list with status "Offline" (since the bot isn't running for seeded scenarios); chat history contains 3 ping/pong message pairs.
- **Cache miss**: if `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst` doesn't exist on this machine, restore auto-calls `regen_echo_peer_seed.sh` to populate. Generation takes a few minutes (launches Toxee, drives via marionette, snapshots). Subsequent restores are fast.
- **Echo peer NOT running**: the bot is intentionally offline during this scenario — the friend appears Offline. Tests that depend on peer being Online belong in `peerHarness=echo_live` scenarios.
- Fixture A+F+hist: A signed in, plaintext profile, friend F in `friends.json`, **pre-seeded** `account_data/<toxA_prefix16>/chat_history/c2c_<toxF_full_64>.json` with `version: 2`, `lastViewTimestamp: 0`, 5 message entries (first text `S14 fixture first message`, last text `S14 fixture last message`, msgIDs `s14-fixture-msg-001`…`-005`)
- F does NOT need to be reachable (network-agnostic)
- `offline_message_queue.json` absent
- `MCP_BINDING=marionette`
- Seed SHA captured pre-launch (`SEED_SHA_BEFORE`)

## Driver
**Launch 1**:
1. Poll snapshot up to 30s for sidebar `<nicknameA>\n(Online|Connecting|Offline)` (don't require Online — S14 reads local)
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → find F's row (last-message preview should be `S14 fixture last message`)
3. `fmt_tap_widget` on the row ref; verify message panel mounted; `official.get_widget_tree({summaryOnly: true})` grep for `TencentCloudChatMessageInput`
4. Snapshot → capture `COUNT_LAUNCH1`, `FIRST_LAUNCH1`, `LAST_LAUNCH1` by scanning bubble labels (or `find.byKey` on `message_list_item:s14-fixture-msg-001`..`-005` once keys land)

**Kill + relaunch**:
5. Shell: `pkill -KILL -f "Debug/Toxee.app/Contents/MacOS/Toxee"`; verify `jq '.messages | length' $HIST_FILE` == 5; capture post-kill SHA
6. Relaunch via `./run_toxee.sh`, reconnect both MCPs

**Launch 2**:
7. Re-open F's conversation (same gestures as Steps 2–3)
8. Snapshot → capture `COUNT_LAUNCH2`, `FIRST_LAUNCH2`, `LAST_LAUNCH2`

After the relaunch step (7), the chat history should still show the seeded ping/pong pairs from the `peerHarness=echo_seeded` fixture (3 pairs as restored) plus the explicit `S14 fixture` N=5 messages that S14 layers on top. The persistence assertion is that ALL messages snapshotted to disk survive the kill+relaunch — this is the verification that history persistence works.

## Assertions
- A2: F's conversation row visible in Step 2 (proves `loadAllHistories` succeeded)
- A3: `COUNT_LAUNCH1 == 5` matches seed
- A4: `FIRST_LAUNCH1 == "S14 fixture first message"`
- A5: `LAST_LAUNCH1 == "S14 fixture last message"`
- A6: relaunch reaches HomePage within 15s, no crash
- A7: `official.get_runtime_errors({})` matches Launch-1 baseline (empty delta at end)
- A8: `COUNT_LAUNCH2 == COUNT_LAUNCH1`
- A9: `FIRST_LAUNCH2 == FIRST_LAUNCH1` AND `LAST_LAUNCH2 == LAST_LAUNCH1`
- A10: `$HIST_FILE` is at per-account `<accountDataRoot>/chat_history/c2c_<toxF>.json`, NOT shared `<appSupport>/chat_history/…` fallback
- A11 (negative): log does NOT contain `[MessageHistoryPersistence] no historyDirectory injected` across either launch
- Negative grep: `post-load save failed for c2c_<toxF>`, `saveHistory error`, `loadHistory error` must NOT appear

## Notes
- Don't seed via live send + kill — debounced `_appendDebounce` (200ms) loses writes on SIGKILL; fixture file is the determinism gate.
- `markConversationViewed` may rewrite the file if any row flagged dirty on load; SHA drift is advisory, A3/A8/A9 are the gates. Anchor `lastViewTimestamp` above all message timestamps for pin-perfect SHA.
- `_appendHistory` writes are per-account via `AppPaths.getAccountChatHistoryPath(toxId)` (`account_service.dart:220-228`); regression to shared dir is the multi-account-corruption mode A10/A11 catch.
- `version: 2` is the current `saveHistory` output; v1 still accepted on read.
- `msgID` is REQUIRED — dedup falls back to fragile `${timestamp}_${fromUserId}` synthetic key otherwise.
