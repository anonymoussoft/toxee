# S65 — Initiate voice call

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1 (B paired, both online)`.
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned (real mic gate + ToxAV media leg cannot be hermeticized).
**Status**: covered by executable Fixture C call gate — `tool/mcp_test/run_fixture_c_call.sh voice` (boots the paired pair online, then `l3_start_call` audio A→B; B observes `call.state==ringing`). Validated live 2026-06-01. Requires macOS mic (TCC) authorization granted for `com.toxee.app`.

## Precondition
- A signed in, online; one C2C conversation with friend B; B's toxee online on DHT (twin).
- `useCallKit == true` — else the `Icons.call` voice button is not rendered (`third_party/chat-uikit-flutter/.../tencent_cloud_chat_message_header_actions.dart:25`; set via `uikit_data_facade.dart:380`).
- macOS mic TCC for `com.toxee.app` pre-granted (see Notes — desktop takes no in-app prompt).
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; poll snapshot ≤60s for sidebar `<nicknameA>\nOnline`.
2. Tap `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → tap B's conversation row.
3. Confirm header `TencentCloudChatMessageHeader` shows `<nicknameB>` + an `Icons.call` IconButton.
4. Prefer `marionette.tap({ key: "chat_call_voice_button" })` via `UiKeys.chatCallVoiceButton`; snapshot-ref / icon matching remains the fallback.
5. Poll log + snapshot ≤5s for outgoing/ringing UI.

## Assertions
- A1: `OutgoingCallView` mounts — snapshot shows `ValueKey('outgoing-call-actions')` (`outgoing_call_view.dart:46`), hang-up labelled `l10n.callHangUp`, subtitle `l10n.callCalling`.
- A2: outgoing/ringing — log `[CallStateNotifier] startRinging: mode=CallMode.audio, direction=CallDirection.outgoing` (`call_state_notifier.dart:94`, debug-only).
- A3: media leg — log `[ToxAVService] startCall: friendNumber=<n> audio=48 video=0` then `[ToxAVService] startCall succeeded: friendNumber=<n>` (`toxav_service.dart:523,538`). Mirror: `[TUICallKitAdapter] _handleCall startCall result=true friendNumber=<n>` (`tuicallkit_adapter.dart:212`).
- A4: no in-app mic prompt — macOS `shouldRequestRuntimePermission()==false` (`permission_helper.dart:32-34`); OS TCC grant is the gate (Precondition).
- Negative: `[ToxAVService] startCall failed` and `[CallServiceManager] Friend <id> is offline, auto-ending` (`call_service_manager.dart:481`, debug-only) must NOT appear.
- A5: `official.get_runtime_errors({})` matches Step-1 baseline.

## Notes
- Still L3-pinned on a real mic/ToxAV environment, but no longer blocked: the executable Fixture C gate above covers the flow once B is online and TCC is pre-granted. Without B online the call auto-cancels in ~800ms (`call_service_manager.dart:480-488`).
- macOS desktop never prompts for mic at runtime (`permission_helper.dart:32`); grant ahead via `tccutil reset Microphone com.toxee.app` + one manual approval (playbook §7b). A revoked grant yields silence / a CoreAudio error, no Dart `not granted` line.
- A2 and `startRinging` markers are `debugPrint`-gated — assert from logs only in the debug L3 bundle, not as a release contract.
- `chatCallVoiceButton`, `callHangupButton`, and `callMicMuteButton` are now shipped anchors. The remaining difficulty in this scenario is the real media environment, not locating the controls.
