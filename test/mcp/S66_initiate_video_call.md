# S66 — Initiate video call

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A1 friends=1 network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned (camera/mic + ToxAV media stack can't be hermeticized).
**Status**: covered by executable Fixture C call gate — `tool/mcp_test/run_fixture_c_call.sh video` (`l3_start_call` with video=true A→B; B observes ringing; both reach `inCall`; A toggles video). Validated live 2026-06-01. Requires macOS camera+mic (TCC) authorization for `com.toxee.app`.

## Precondition
- A signed in, online; one C2C friend B, online and reachable over live DHT.
- macOS Camera + Microphone permission for `com.toxee.app` = Granted (see Notes — pre-grant via `tccutil`).
- B is a second toxee process (Fixture C) able to answer, or local camera preview cannot engage (capture only starts after peer-accept).
- Conversation with B open in the message view.

## Driver
1. Open conversation with B. The header video button is a bare `IconButton(icon: Icons.videocam)` with **no UiKey** (`third_party/chat-uikit-flutter/.../tencent_cloud_chat_message_header_actions.dart:36`) — locate via `arenukvern.fmt_semantic_snapshot` (videocam icon ref).
2. `arenukvern.fmt_tap_widget(ref=<videocam ref>)`; fall back to `marionette.tap` if it no-ops.
3. Wait ≤2s for the ringing surface to mount.
4. Have B (second process) accept; wait ≤5s for the inCall transition.

## Assertions
- `OutgoingCallView` (`outgoing_call_view.dart:11`) mounts with `CallActionDock(key: ValueKey('outgoing-call-actions'))`; subtitle reads `l10n.callVideoCall` (`isVideo == true`). Ringing view is identity-stage only — no local preview yet.
- Log: `[ToxAVService] startCall: friendNumber=<n> audio=48 video=2000` then `[ToxAVService] startCall succeeded: friendNumber=<n>` (`toxav_service.dart:523,538`; `videoBitRate=2000` per `tuicallkit_adapter.dart:190`).
- Debug-only `debugPrint` markers: `[CallServiceManager] _onOutgoingCallInitiated: ... type=video` (`call_service_manager.dart:456`); after B answers, `[CallServiceManager] _onCallState: ... state=<bits>` with SENDING_A/ACCEPTING_A set (`call_service_manager.dart:623,664`) → `enterCall()` → `_startMediaCapture` (`call_service_manager.dart:670`).
- Capture engages post-accept only: `[VideoHandler] macOS capture started (camera_macos stream active)` (`video_handler.dart:314`); `localPreview != null` (`call_service_manager.dart:111`). Denied camera → `[VideoHandler] startCapture macOS: no video devices (check Camera permission)` (`video_handler.dart:285`).

## Notes
- Still L3-pinned on real camera/mic/ToxAV behavior, but no longer blocked: the executable Fixture C gate above covers the flow once TCC is pre-granted.
- macOS `CallPermissionHelper.shouldRequestRuntimePermission` returns false (`permission_helper.dart:24-36`), so no in-app prompt fires; the OS camera/mic dialog is raised lazily by `camera_macos` at capture time — pre-grant with `tccutil reset Camera com.toxee.app` + `tccutil reset Microphone com.toxee.app`, then approve once, or stage a TCC-granted profile (§7b).
- Local preview only engages after peer-accept (`_startMediaCapture` runs on inCall, not on ring), so the live twin remains a hard precondition even though the scenario now has an executable Fixture C gate.
- `[VideoHandler]` / `[CallServiceManager]` markers are `debugPrint`/`AppLogger` lines — present only in debug builds (the L3 standalone bundle is debug).
