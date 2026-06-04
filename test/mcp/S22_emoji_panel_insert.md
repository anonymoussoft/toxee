# S22 — Emoji panel insertion

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: **L2 candidate once harnessed.** The render-only path needs real bundled assets + real plugin lifecycle + real widget tree — all L2-reachable (no live DHT, F may be offline). The `tencent_cloud_chat_sticker` plugin registers in `HomePage._initAfterSessionReady` which L2's host-bundle init exercises. Send-side bubble assertions (A6/A7) are deterministic against a stub friend; an integration_test smoke can hold the assertions. Sibling of S23 (sticker/custom-face panel).
**Status**: covered

## Precondition
- Account A logged in, plaintext, sidebar reached `<nicknameA>\nOnline` (or `Connecting`)
- One friend F (A-friend1 fixture) — online preferred but offline works for the render-only path
- Sticker plugin registered: log contains `[HomePage] Sticker plugin registered successfully` and `Plugin initData.customStickerLists: <N> items` with N ≥ 4
- Bundled asset `flutter_assets/packages/tencent_cloud_chat_sticker/assets/stickers/emoji_0.png` present (build sanity)

## Driver
1. `marionette.tap({ key: "sidebar_chats_tab" })`
2. Locate F's conversation row in semantic snapshot; `fmt_tap_widget` to open
3. Tap the emoji/sticker trigger in the message-input control bar — desktop: tooltip matches `tL10n.sticker` ("Stickers"/"表情"); mobile: `Icons.emoji_emotions` `GestureDetector` near input row. Wait ~200ms for the panel's 60ms ease-in to settle.
4. Identify the default-emoji tab by `iconPath == 'assets/stickers/emoji_0.png'` (tab index varies based on plugin `useDefaultCustomFace_*` flags) and tap it
5. Tap the first grid cell (top-left); this is `[TUIEmoji_Smile]` per `tencent_cloud_chat_sticker_default.dart:2`
6. Send via `fmt_press_key({ key: "Enter" })` (desktop) or send button (mobile)

## Assertions
- A1: log shows sticker plugin registration before scenario starts
- A3: emoji panel mounted — desktop `TencentCloudChatDesktopStickerPanel` in widget tree; no `TencentCloudChatStickerError` ("暂无表情") node
- A4: input field text becomes exactly `" [TUIEmoji_Smile]"` (leading space because the empty-field branch fires `space = " "` in `tencent_cloud_chat_message_input_desktop.dart:86-100`)
- A5: input field cleared after send
- A6 (primary): outgoing bubble renders the emoji as an inline image, not literal text. Probe via `official.get_widget_tree({ summaryOnly: true })` — look for an `Image`/`AssetImage` descendant with asset name ending in `assets/stickers/emoji_0.png` and `package: 'tencent_cloud_chat_sticker'`. Negative: no `Text` widget with literal `[TUIEmoji_Smile]` content
- A7 (online): log contains `[Tim2ToxSdkPlatform] sendMessage called` + `[FfiChatService]` send lines. Persisted history entry has `text == " [TUIEmoji_Smile]"` (token transported as plain text; image substitution is client-side at render only)
- A8: `official.get_runtime_errors({})` empty vs Step 1 baseline
- Negative grep: `TencentCloudChatStickerError`, `[FfiChatService] ... send ... exception` MUST NOT appear

## Notes
- Mobile path's `uikitListener` deliberately does NOT call `closeSticker()` — panel staying open on mobile is expected
- `EmojiText.finishText()` early-returns to literal text when `stickerPluginInstance == null` — A6 failure with A1 passing suggests the bubble was built before the plugin was threaded through `MessageInputBuilderData.stickerPluginInstance`
- Wanted UiKeys (in UIKit fork, user-owned): `message_emoji_panel_trigger`, `message_emoji_panel`, `emoji_panel_tab:<index>`, `emoji_panel_item:<name>`
- For the "type-text-then-emoji" variant the leading-space branch does NOT fire — track as S22b
