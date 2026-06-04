# S18 — Reply / quote a message

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded(2)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because exercises cloudCustomData → `[REPLY_START]…[REPLY_END]` Tox encoding via real `MessageReplyUtil` C++ path; needs UIKit-fork menu-item + reply-banner keys for stable targeting
**Status**: covered (online + offline variants)

Shares menu-open path with S15/S17. Layered tests: menu surface (S15), forward (S17), reply data path (S18).

## Precondition
- Fixture A-with-replyable-history: A signed in, plaintext, friend F in `friends.json`, `messages/c2c_<toxF>.json` seeded with ≥2 entries — at least one with `fromUserId: <toxF>` (`isSelf: false`): ① `{msgID:"seed_0", fromUserId:<toxF>, text:"heads-up: ci broke", timestamp:<t-60s>}` ② `{msgID:"seed_1", fromUserId:<toxA>, text:"on it", timestamp:<t-30s>}` (both SEND_SUCC on history load)
- Locale pinned (`en`: `Reply`; `zh`: `回复`)
- `MCP_BINDING=marionette`

Variants: online (default — `pending → sent`) or offline (queued with cloudCustomData preserved in `offline_queue.json`).

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`; baseline runtime-errors
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`)
3. `fmt_tap_widget` on F's conversation row; verify chat panel mounted with both seed bubbles
4. `marionette.long_press` on the received `heads-up: ci broke` bubble (`ref` from snapshot, or `key: "message_list_item:seed_0"` once available) → context menu opens
5. `fmt_tap_widget` on menu item with label `Reply` / `回复` (or `key: "message_menu_item_reply"` once UIKit fork lands)
6. Re-snapshot ≤500ms → quote banner mounted above input (sender `<friendName>` + abstract `heads-up: ci broke` + `Icons.cancel_outlined`)
7. `marionette.enter_text` on `message_input_field` with `re: thanks for the heads-up` (fallback `fmt_enter_text` on unique text-field ref)
8. Send via `fmt_press_key({key: "Enter"})` on desktop (or `marionette.tap({key: "message_send_button"})` on mobile)
9. Re-snapshot ≤2s; poll log for `[Tim2ToxSdkPlatform] sendMessage called`
10. (optional Step 9-cancel sub-flow): re-trigger banner, `fmt_tap_widget` on the cancel icon, verify banner gone but input text retained

## Assertions
- A1: menu opens after Step 4 (snapshot contains `Reply`/`回复` label)
- A2: `Reply` item present (gated on `_message.status == SEND_SUCC`)
- A3: after Step 5, snapshot contains banner region with `<friendName>` + `heads-up: ci broke` + cancel icon
- A4: after Step 7, snapshot shows input field labeled `re: thanks for the heads-up`
- A5: after Step 8, banner gone from snapshot (no `<friendName>` + `heads-up` pair near input area)
- A6: after Step 8, input field empty
- A7: new outgoing bubble at message-list tail labeled `re: thanks for the heads-up` (self / right side)
- A8: new bubble subtree contains a reply pill labeled with `<friendName>` + `heads-up: ci broke` prefix (`TencentCloudChatMessageReplyView`)
- A9 (online): log contains `[Tim2ToxSdkPlatform] sendMessage called: id=` then `Found message: msgID=`; with `_debugLog=true`, `messageToSend.cloudCustomData={"messageReference":{"messageID":"seed_0","messageAbstract":"heads-up: ci broke","messageSender":"<toxF>",...}}`
- A9' (offline): new `offline_queue.json` entry has `cloudCustomData != null` and decoded JSON has `messageReference` key
- A10 (optional post-relaunch): `messages/c2c_<toxF>.json` last entry `text` starts with `[REPLY_START]` and contains embedded messageReference JSON; on re-open, reply pill re-renders (round-trips through `parseReplyMessage`, `tim2tox_sdk_platform_converters.dart:76-107`)
- A11: `official.get_runtime_errors({})` matches baseline
- A12 (optional cancel-banner): banner gone after cancel-icon tap; input text retained (cancel only clears `quotedMessage`)
- Negative grep: `[Tim2ToxSdkPlatform] sendMessage failed:`, `Failed to parse reply message:`, `A RenderFlex overflowed` must NOT appear

## Notes
- Input controller's `text` does NOT contain `[REPLY_START]` literal — markers are injected by `MessageReplyUtil` during send (cloudCustomData path).
- `_textEditingController.clear()` and `dataProvider.quotedMessage = null` are not in the same microtask; snapshot at +250ms after send for A5+A6 to settle.
- `messageAbstract` is `TencentCloudChatUtils.getMessageSummary` output — long texts get ellipsized; use substring match (not equality) for A3/A8.
- Self-reply is legal but semantically weak — fixture should seed at least one received message and reply to it.
- toxee does NOT currently register `messageInputReplyBuilder` / `messageReplyViewBuilder`; UIKit defaults render fine. Key-anchored A8/A3 require those builders to wrap with `KeyedSubtree`.

## Coverage note (2026-06-02) — DATA HALF FIXED + GATED

**Runner gate (data half)**: `tool/mcp_test/scenarios/l3_reply_text.json` (hermetic).

The feature-plumbing fix this note previously called for **has LANDED** (2026-06-02, self-validated — codex was down; codex diff-review owed):
- `ChatMessage` now has a nullable `cloudCustomData` field (gated toJson, null-safe fromJson, copyWith) — backward-compatible (17/17 persistence unit tests incl. a new on-disk round-trip + legacy-load test).
- `FfiChatService.sendText` gained an optional `cloudCustomData` param, set on the online-branch ChatMessage so the reply quote PERSISTS sender-side (survives reload — that was the actual regression).
- New L3 tool `l3_reply_text` builds the `{"messageReply":{...}}` cloudCustomData and sends via the widened `sendText`; new `l3_dump_state.messages[].cloudCustomData` field; new runner `message_field_contains` assertion. The gate sends a base message, replies (`replyToText` + `replyToIsSelf:true`), and asserts the SELF reply persists with `cloudCustomData` containing `messageReply` + the base text.

**Still scoped out (documented follow-ups):** the quote is NOT sent over the Tox wire (`_ffi.sendText` carries plain text — the peer never sees it; the C++ `[REPLY_START]…[REPLY_END]`/`MessageReplyUtil` encoding A10 relies on is a separate effort), and the OFFLINE-queue branch does not carry `cloudCustomData`. So this gates the SENDER-SIDE PERSISTENCE half, not end-to-end delivery.
- Reply `cloudCustomData` shape (for the eventual gate), built at `third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/model/tencent_cloud_chat_message_data_tools.dart:81`: `{"messageReply":{messageID, messageTimestamp, messageSeq, messageAbstract, messageSender, messageType, version}}`. (Note: the UIKit reply-compose path emits the `messageReply` key; the older `messageReference` shape referenced in A9/A9' above is the runtime-decoded variant — the deferred gate should assert against whichever the plumbing change actually persists.)
