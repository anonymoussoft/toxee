# S23 — Sticker panel (custom face) → directly sends a face message

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the path is "tap → automatic send" (no Enter), needs the sticker plugin's `getStickerWidgetForMessageItem` asset lookup, and exercises the `__face__:{json}` wire serialization. Sibling of S22 (emoji insertion). The defining invariant: tapping a custom face MUST NOT touch the input text.
**Status**: covered

## Precondition
- Account A logged in, plaintext, sidebar Online/Connecting
- One friend F (A-friend1 fixture); online for the wire-send variant, offline for the queue variant
- Sticker plugin registered: log contains `[HomePage] Sticker plugin registered successfully` AND `[HomePage] Sticker panel widget retrieved: true` AND `customStickerLists: 4 items`
- `account_data/<toxA>/messages/c2c_<toxF>.json` exists (empty OK)

## Driver
1. `marionette.tap({ key: "sidebar_chats_tab" })`; open F's conversation
2. Tap the sticker entry in the attachment bar (label `tL10n.sticker` "表情"/"Sticker"). Wait ≥200ms for the 60ms `delay300` panel ease-in.
3. Verify panel tabs visible (icons match `gcs00@2x.png`, `ys00@2x.png`, `yz00@2x.png`, `emoji_0.png` — note: exact left-to-right order depends on plugin's LIFO `insert(0,...)`; verify against a screenshot golden, not a hard-coded index)
4. Switch to the gcs tab if not already active
5. Tap the top-left grid cell (`gcs00@2x.png`, name `[gcs00]`)

## Assertions
- A4: panel tabs render with the four expected icons
- A6: panel closes synchronously after the tap (desktop `uikitListener` calls `closeSticker()` for type==1)
- A7: one new outgoing bubble appears containing an `Image` widget at ~100px width (from `getStickerWidgetForMessageItem`), NOT a text widget
- A8 (defining S23 invariant): input field text is UNCHANGED (no `[gcs00]`, no `[ys..]`, no `[yz..]`, no `[TUIEmoji_*]`). This is what distinguishes S23 from S22.
- A9 (online): log contains `[Tim2ToxSdkPlatform] sendMessage called` → `[Tim2ToxSdkPlatform] Sending face message: __face__:{` → `Face message sent successfully` (use tolerant prefix grep; do not pin JSON field order)
- A9' (offline): log contains `[FfiChatService] _queueOfflineText`; `account_data/<toxA>/offline_queue.json` gains an entry whose `text` starts `__face__:{`
- A11: `official.get_runtime_errors({})` empty vs baseline
- Negative grep: `TencentCloudChatStickerError`, `[Tim2ToxSdkPlatform] sendMessage failed:` MUST NOT appear

## Notes
- Type-1 routing happens in `tencent_cloud_chat_message_separate_data.dart:302-310` (calls `sendFaceMessage`); the desktop input listener at `tencent_cloud_chat_message_input_desktop.dart:86-100` for type==1 only calls `closeSticker()`, leaving text untouched
- Face is shipped over Tox's text channel as `__face__:{"index":1,"data":"[gcs00]"}` — there is no native Tox sticker channel; receiver renders as literal text (documented, out of scope here — sender-side scenario only)
- Default-emoji tab position depends on `useDefaultSticker` + `useDefaultCustomFace_*` LIFO; verify with `customStickerLists` log line + `iconPath` match. Don't hard-code the index.
- Wanted UiKeys (UIKit fork): `chat_input_sticker_button`, `chat_sticker_panel_container`, `chat_sticker_panel_tab:<packIndex>`, `chat_sticker_grid_item:<packIndex>:<name>` — shared with S22's set
