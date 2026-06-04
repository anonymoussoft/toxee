# S12 — Send a text message

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L2 candidate once the keyed composer + per-message row path is promoted end-to-end; the core anchors now exist (`chat_input_text_field` via toxee's `messageInputBuilder` wrapper, plus UIKit's `message_list_item:<msgID>` row key), but desktop send is still primarily Enter-driven and status icons remain non-semantic.
**Status**: covered (online + offline variants)

## Precondition
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` — idempotent; on first call, builds + launches the bot if needed; waits for ID emission. Reads `tool/mcp_test/echo_peer.json` to capture `peer_id` (76-char Tox address). Bot auto-accepts friend requests + echoes received c2c text verbatim.
- **DHT warmup**: scenario runner should wait for `_drive_seed.dart`-style logic to confirm peer is DHT-reachable from the toxee side before proceeding — typically 5-30s; use a poll-for-peer-Online loop, not a fixed sleep.
- **Cleanup**: scenario runner should call `bash tool/mcp_test/stop_echo_peer.sh` in teardown (or rely on session-level reuse if running a batch).
- Fixture A+friend1: A signed in, plaintext profile, friend F in `friends.json`, `messages/c2c_<toxF>.json` empty list or seeded
- **A-friend1-online**: F reachable on DHT → expected `pending → sent`
- **A-friend1-offline**: F's toxee not running → expected `pending`/`queued` in `offline_queue.json`
- `MCP_BINDING=marionette`

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`; baseline `official.get_runtime_errors({})`
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → find F's conversation row
3. `fmt_tap_widget` on the row ref; re-snapshot → confirm `TencentCloudChatMessageHeader` with `<friendName>` + input field at bottom
4. Enter text: target the keyed composer wrapper `UiKeys.chatInputTextField` (`chat_input_text_field`) and enter `hello toxee MCP test`. If the automation layer cannot focus the descendant field through the wrapper, fallback `fmt_enter_text` on the unique text-field ref in the chat panel subtree.
5. Send: prefer `fmt_press_key({key: "Enter"})` on desktop. Fallback: append `\n` in `enter_text`. Mobile/tablet may expose a send affordance inside the same keyed composer surface, but desktop remains Enter-driven.
6. Re-snapshot ≤2s; poll log for `[Tim2ToxSdkPlatform] sendMessage called`

## Assertions
- A1: chat panel mounted after Step 3 — `TencentCloudChatMessageHeader` with `<friendName>` + input field present
- A2: after Step 4, snapshot shows input field labeled `hello toxee MCP test`
- A3: after Step 5, input field empty (no `hello toxee MCP test` label on the text field)
- A4: new outgoing bubble in message list — snapshot contains a node with `hello toxee MCP test` separate from the input
- A5 (online): log contains `[Tim2ToxSdkPlatform] sendMessage called: id=` then `Looking for message in targetID: <toxF>` then `Found message: msgID=` then `[FfiChatService]` send lines, with NO `_queueOfflineText`
- A5' (offline): log contains `[FfiChatService] _queueOfflineText` (or `_addToOfflineQueue`); bubble status pending/queued; `account_data/<toxA>/offline_queue.json` grows by one entry
- A7: `official.get_runtime_errors({})` matches Step-1 baseline
- A8: conversation row's last-message preview updates to `hello toxee MCP test` (poll ≤1.5s for FakeChatMessageProvider debounce)
- A9 (echo arrival, online only): wait for the **second occurrence** of the sent text `hello toxee MCP test` in the conversation panel (echo peer mirrors verbatim — no `echo:` prefix; see `tool/mcp_test/echo_peer_src/echo_peer.cpp:85`). This is the verbatim-mirror contract — assertion fails if the bot prefixes or transforms the text.
- Negative grep: `[Tim2ToxSdkPlatform] sendMessage failed:` must NOT appear

## Notes
- Status icons (pending/sent/queued) are rendered by UIKit without semantic labels — verify via log markers + `offline_queue.json`, not snapshot.
- Send branches on the **pre-check** friend.online value (`ffi_chat_service.dart:3564`); flips mid-test won't change path.
- Don't start Step 4 until Step 1's `\nOnline` lands, or online send silently becomes offline (`friend.online == false` at send time).
- A6 (persistence) doubles up with S14; leave as smoke unless S12 is run alone.
