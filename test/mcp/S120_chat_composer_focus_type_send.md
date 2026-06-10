# S120 — Chat composer: input field focus + type + send

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L2/L1 — the deterministic typing+Enter→real-send is ALREADY a PASSING WidgetTester (`test/ui/chat_core_real_ui_test.dart:191`, "desktop composer: typing + Enter invokes the real send path"). The live-DHT round-trip stays L3 (a real peer is L3-only).
**Status**: **covered (L1 WidgetTester gates exist for both the DESKTOP typing + Enter → real send AND the MOBILE in-row send affordance; live send is L3).** The marionette desktop send needs a REAL OS Return (synthetic Enter does NOT reach the legacy `RawKeyEvent` handler); the deterministic send→persist assertion belongs at L1 (REAL_UI_GATES #1). The MOBILE leg ("mobile sends via the in-row send affordance", below) is now covered at the widget layer (L1): typing into the real `TencentCloudChatMessageInputMobile` field reveals the production send button (an empty field shows the press-to-record mic instead) and tapping it drives the real `sendTextMessage` path.
**Covered-by**: test/ui/chat_core_real_ui_test.dart (desktop Enter→send); test/ui/mobile/mobile_composer_real_ui_test.dart (mobile in-row send affordance, L1)

> The composer is the toxee override boundary (`KeyedSubtree(key: UiKeys.chatInputTextField)`, home_page_bootstrap.dart:628-629) wrapping the UIKit fork input. S120 = focus the composer, type, and send; assert the self message persists. Desktop send is Enter-only (no tappable Send button); mobile sends via the in-row send affordance.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` (idempotent; captures `peer_id` from `tool/mcp_test/echo_peer.json`; bot mirrors c2c text verbatim, no prefix — `tool/mcp_test/echo_peer_src/echo_peer.cpp:85`). Teardown `bash tool/mcp_test/stop_echo_peer.sh`. Peer must reach Online (poll, don't sleep) or the online send silently becomes the offline branch.
- Account A logged in, plaintext, sidebar Online (poll ≤60s). Peer-connected confirmed in log (`[V2TIMManagerImpl] HandleFriendConnectionStatus: ENTRY - friend_number=<n>, connection_status=2`, V2TIMManagerImpl.cpp:5858; older S62 cites the pre-growth offset :5846).
- F's conversation open: tap `UiKeys.conversationListTile("c2c_<toxF>")` (`conversation_list_item:c2c_<toxF>`, fork tencent_cloud_chat_conversation_list.dart:118) → the message panel mounts with `TencentCloudChatMessageHeader` showing `<nickF>`.
- The composer `UiKeys.chatInputTextField` (`chat_input_text_field`, attached at home_page_bootstrap.dart:629) is present at the bottom of the mounted panel.

## Executable Driver

```bash
flutter test test/ui/chat_core_real_ui_test.dart --plain-name 'desktop composer: typing + Enter invokes the real send path'
```

This is the PASSING, CI-runnable, deterministic gate (REAL_UI_GATES #1). It renders the fork composer in a WidgetTester, types via `testTextInput.enterText` (the composer is an `ExtendedTextField`, so `tester.enterText` FAILS — see REAL_UI_GATES recipe §3), asserts **no send before Enter** (non-vacuous), then `sendKeyEvent(LogicalKeyboardKey.enter)` → the real `_handleKeyEvent` → `sendTextMessage` (desktop input `tencent_cloud_chat_message_input_desktop.dart:545/574). It covers exactly the send path marionette cannot inject on desktop. The LIVE-DHT round-trip (real persist + echo arrival) is the L3 UI flow below; the deterministic callback gate is this WidgetTester.

## UI Driver
1. With F's conversation open (precondition), baseline `official.get_runtime_errors({})` and capture the peer's current `messages[]` length from `l3_dump_state`.
2. Focus + type: `marionette.enter_text(UiKeys.chatInputTextField, "S120 compose <nonce>")`. The `chat_input_text_field` key wraps the WHOLE input row (text field + attachment + send affordances, home_page_bootstrap.dart:621-627); marionette delivers to the focused descendant `ExtendedEditableText`. If the wrapper key cannot directly focus the descendant in this harness, fall back to `fmt_enter_text` on the unique chat-panel text-field ref (the S12/S62 idiom).
3. Send:
   - **DESKTOP**: synthetic Enter does NOT reach the legacy `RawKeyEvent` handler (`_handleKeyEvent` reads `RawKeyDownEvent`, desktop input :554; gated send at :560/574). Send via a REAL OS Return: foreground the Toxee window, then `osascript -e 'tell application "System Events" to key code 36'` (the validated S62/S12 workaround). Do NOT rely on `fmt_press_key({key:"Enter"})`.
   - **MOBILE**: tap the in-row send affordance. NOTE: it is the fork's `InkWell`/`onTap` → `sendTextMessage` (mobile input `tencent_cloud_chat_message_input_mobile.dart:586-590), which lives INSIDE the `chat_input_text_field`-wrapped row; it is NOT separately keyed (`UiKeys.chatSendButton` is DEFINED but UNATTACHED today — ui_keys.dart:289; see Notes). Target it by the send icon ref within the composer subtree.
4. Re-snapshot ≤2s; poll `l3_dump_state` for the new self message; poll the log for the send-path markers.

## Assertions
- A1 (typed): after Step 2, the composer shows `S120 compose <nonce>` (snapshot text on the `chat_input_text_field` subtree).
- A2 (self message persists, primary): after Step 3, `l3_dump_state.messages[]` for the peer gains a row with `text == "S120 compose <nonce>"` and `isSelf == true` (l3_debug_tools.dart:3762-3764). The conversation row's `lastMessageText` updates to the same text (`conversations[].lastMessageText`, l3_debug_tools.dart:3646).
- A3 (send-path markers, unconditional): the log fires, in order, `[Tim2ToxSdkPlatform] sendMessage called: id=` (tim2tox_sdk_platform.dart:5012, unconditional `print`) → `[Tim2ToxSdkPlatform] Found message: msgID=` (:5051, unconditional). Do NOT require the `if (_debugLog)`-gated `Looking for message in targetID:` line (:5028). (Line numbers verified against the current submodule; the older S62/S12 docs cite the pre-growth offsets — same markers, same gating.)
- A4 (composer cleared): after Step 3, the composer no longer shows `S120 compose <nonce>` (the send clears the field).
- A5 (no offline branch): `[FfiChatService] _queueOfflineText` (ffi_chat_service.dart:3863, called at :3826) MUST NOT appear — both online means the live send path, not the S25 offline queue. If it fires, the peer wasn't actually Online at send time (fix the fixture, don't relax A3).
- A6 (echo arrival, live): wait ≤30s for a SECOND occurrence of `S120 compose <nonce>` as an INBOUND row — `l3_dump_state.messages[]` gains a row with the same text and `isSelf == false` (echo mirrors verbatim, no prefix). This is the live round-trip (shared with S12 A9).
- Negative grep: `[Tim2ToxSdkPlatform] sendMessage failed:` (tim2tox_sdk_platform.dart:5123/5149/5418/5566 — the message-not-found / no-provider / unsupported-type / catch-all variants) MUST NOT appear.
- A7: `official.get_runtime_errors({})` matches the Step-1 baseline.

## Notes
- Status note: the deterministic typing+Enter→send is a PASSING L1 WidgetTester (REAL_UI_GATES #1, `chat_core_real_ui_test.dart:191`) — that is the "covered (executable)" half. The live send + echo (A2/A6) is L3 (needs a real peer + DHT). Do NOT claim the live L3 flow is executable.
- Key verified: `chatInputTextField` @ home_page_bootstrap.dart:629 (toxee `KeyedSubtree(key: UiKeys.chatInputTextField, ...)`; defined ui_keys.dart:288). **`chatSendButton` (ui_keys.dart:289) is DEFINED but NOT attached to any widget in `lib/`** — its doc (ui_keys.dart:281-287) reserves it for the mobile send-icon row, but today the mobile send `InkWell` (fork mobile input :586) sits inside the `chat_input_text_field` wrapper unkeyed. Treat `chatSendButton` as a reserved/forward-looking anchor, not a live tap target; on mobile, tap the send icon by ref.
- Desktop send mechanics: `_handleKeyEvent` is bound via `_textEditingFocusNode.onKey` (desktop input :73) and only acts on `RawKeyDownEvent` (:554) — Flutter's synthetic key injection does NOT produce the raw event the legacy handler reads, hence the real OS `key code 36` (S62/S12). Shift/Alt/Ctrl/Meta+Enter inserts a newline instead of sending (:560), so the Return must be unmodified.
- Sibling distinction: S12 = send a text message (echo round-trip, single instance); S62 = two-process real-time delivery (A↔B). S120 focuses the COMPOSER widget specifically (the keyed wrapper + the desktop-Enter-vs-mobile-send split); reuse S12/S62 for the live-delivery assertions (A6).
- Mobile parity: the composer wrapper and `sendTextMessage` are SHARED Dart (toxee builder boundary + fork mobile/desktop inputs) — iOS/Android render `tencent_cloud_chat_message_input_mobile.dart` and send via the same `inputMethods.sendTextMessage`. The desktop-only divergence is the Enter handler (`..._input_desktop.dart`) vs the mobile send InkWell (`..._input_mobile.dart`); S120 addresses both legs (Step 3 desktop vs mobile). The composer is an `ExtendedTextField`, so a WidgetTester promotion must use `testTextInput.enterText`, not `enterText` (REAL_UI_GATES recipe §3).
