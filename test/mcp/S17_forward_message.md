# S17 — Forward a message to another conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=2 history=seeded`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because picker is UIKit `TencentCloudChatDesktopPopup` overlay / `showModalBottomSheet` with no toxee builder slot; needs UIKit-fork keys for stable targeting
**Status**: covered (online default + offline-target + multi-target sub-variants). Also covered at the widget layer (L1) by WidgetTester real-UI gates: the desktop gate drives the REAL `Forward` menu item tap → `TencentCloudChatDesktopPopup` forward-picker overlay → target-row selection → `Send` → asserts the real `createForwardMessage` and `sendMessage` recording SDK calls. The mobile gate now drives the FULL chain: long-press → `Forward` item → bottom-sheet opens without layout overflow → target selected → `Send` → asserts `createForwardMessage` and `sendMessage` recording calls. The prior mobile overflow bug (Row without Expanded in `_renderHeader()` at `tencent_cloud_chat_message_forward.dart:44`) was fixed (2026-06-10); the mobile gate is no longer presence-only.
**Covered-by**: test/ui/chat/message_actions_menu_real_ui_test.dart (desktop; full end-to-end), test/ui/chat/message_actions_menu_mobile_real_ui_test.dart (mobile; full end-to-end including overflow fix)

Shares menu-open path with S15/S18.

## Precondition
- Fixture A-with-two-friends-and-replyable-history: A signed in, plaintext, friends `<toxF1>` + `<toxF2>` in `friends.json`
- `messages/c2c_<toxF1>.json` seeded with `[{msgID:"seed_src", fromUserId:<toxF1>, text:"original payload to forward", timestamp:<t-60s>}]` (SEND_SUCC stamped on load)
- `messages/c2c_<toxF2>.json` seeded with at least one message (so `<toxF2>` appears in picker's Recent tab)
- Locale pinned to `en` (picker header: `Cancel` / `Forward Individually` / `Send`; tabs: `Recent` / `Contacts` / `Groups`)
- `MCP_BINDING=marionette`

Variants: online (default), offline-target (`<toxF2>` offline → entry in `offline_queue.json`), multi-target (3 friends, pick 2 in picker).

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`; baseline runtime-errors
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → both `<friendName1>` and `<friendName2>` rows visible
3. `fmt_tap_widget` on `<friendName1>` row; verify chat panel mounted with `original payload to forward` bubble
4. `marionette.long_press` on the source bubble (`ref` from snapshot, or `key: "message_list_item:seed_src"` once available) → context menu opens
5. `fmt_tap_widget` on menu item with label `Forward` (or `key: "message_menu_item_forward"` once UIKit fork lands)
6. Snapshot → picker mounted (`Cancel` / `Forward Individually` / `Send` header + 3-tab TabBar + `<friendName2>` row in Recent)
7. `fmt_tap_widget` on the `<friendName2>` row in the picker (or `key: "message_forward_target:<toxF2>"`) → row highlights, chip becomes `1 chat`
8. `fmt_tap_widget` on header `Send` button (or `key: "message_forward_picker_send"`)
9. Re-snapshot for source-conversation invariance; switch to `<friendName2>` row in sidebar; snapshot for forwarded bubble
10. Poll log up to 500ms for cache-cleanup window

## Assertions
- A1: menu opens after Step 4 (snapshot contains `Forward` label)
- A2: `Forward` item present (gated on `enableMessageForward && status == SEND_SUCC`)
- A3: picker mounted after Step 5 with `Cancel` + `Forward Individually` + `Send` + tabs + `<friendName2>` row
- A4: after Step 7, snapshot contains `1 chat` chip (`tL10n.numChats(1)`)
- A5: after Step 8, picker is gone (no `Forward Individually` title / `Recent` tab)
- A6: source conversation A unchanged — snapshot still shows only the seed bubble, no second `original payload to forward` bubble in A
- A7: target conversation B has new outgoing bubble (self / right-side) with text `original payload to forward` at message-list tail
- A8: target bubble subtree does NOT label `<friendName1>` as sender (forwarded message has sender cleared and refilled to self)
- A9 (online): log contains, in order:
  - `[Tim2ToxSdkPlatform] Found original message: msgID=seed_src, elemType=V2TIM_ELEM_TYPE_TEXT`
  - `[Tim2ToxSdkPlatform] Cached forward message with id: <ts>_forward_<selfId>`
  - `[Tim2ToxSdkPlatform] sendMessage called: id=<ts>_forward_<selfId>, receiver=<toxF2>`
  - `[Tim2ToxSdkPlatform] Message not found in messageData, checking forward message cache for id: <ts>_forward_<selfId>`
  - `[Tim2ToxSdkPlatform] Found message in forward cache: msgID=<ts>_forward_<selfId>`
  - `[Tim2ToxSdkPlatform] ChatMessageProvider found, sending message type: V2TIM_ELEM_TYPE_TEXT`
  - `[Tim2ToxSdkPlatform] Tracking forward message target: text="original payload to forward", userID=<toxF2>`
- A9' (offline): `offline_queue.json` has new entry with `target=<toxF2>`, `text="original payload to forward"`, `cloudCustomData=null` (no `messageReference` unlike reply)
- A10 (optional, post-relaunch smoke): `messages/c2c_<toxF2>.json` last entry text == `original payload to forward`, no `[REPLY_START]` marker
- A11: `official.get_runtime_errors({})` matches baseline
- A12 (multi-target): same `Cached forward message with id` + `sendMessage called` appear N times for N targets
- Negative grep: `createForwardMessage failed:`, `Message not found in forward cache. Cache keys:`, `sendMessage failed: Message not found`, `A RenderFlex overflowed`, `RangeError` must NOT appear

## Notes
- `createForwardMessage` (`tim2tox_sdk_platform.dart:4690`) clones elemType/elements into a new V2TimMessage with fresh msgID `<now_ms>_forward_<selfId>`, **clears sender/nickName/userID/groupID**, caches under `_forwardMessageCache[forwardMsgID]`.
- `_pendingForwardTargets[messageText]` is keyed by **text** (not msgID); same-text forwards collide — known issue, A12 fixture should avoid duplicate text per target.
- Picker is OverlayEntry (desktop) or modal route (mobile); may not appear in `fmt_semantic_snapshot` root tree — fall back to `marionette.get_interactive_elements()`.
- No over-the-wire "forwarded" marker — receiver sees plain text; "forwarded" identity is client-side only.
- Picker header has two `TextButton`s (Cancel + Send); locale-pinned `en` keeps Send label unique.

## Coverage note (2026-06-02)
No executable runner gate (no `**Runner gate**` line) — a data-half L3 gate is **DEFERRED** because the forward path is wire-degraded at the Dart service layer:
- `Tim2ToxSdkPlatform.sendMessage` accepts a `cloudCustomData` param (`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:4991`) but the text-element branch calls `provider.sendText(userID:, groupID:, text:)` with **only the plain text** (`tim2tox_sdk_platform.dart:5169`) — `cloudCustomData` is never forwarded to the wire and `FfiChatService.sendText(String peerId, String text)` has no slot for it.
- The persisted `ChatMessage` model (`third_party/tim2tox/dart/lib/models/chat_message.dart`) has **no `cloudCustomData` field**, so nothing per-message survives a round-trip even on the receiving/persistence side. (Forward currently sends no `messageReply`/`messageReference` payload anyway — see A9' "`cloudCustomData=null`" above — so this matches S17's existing "plain text only" behavior, but the data-half is unreachable to assert regardless.)
- A gate here would therefore test a wire-degraded feature. It is deferred pending a feature-plumbing change: add `cloudCustomData` to `ChatMessage` + an optional `cloudCustomData` param to `FfiChatService.sendText`, then add `l3_forward_message` + a `messages[].cloudCustomData` `l3_dump_state` field to make the data half assertable.
