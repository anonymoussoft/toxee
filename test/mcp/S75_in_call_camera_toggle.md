# S75 — In-call camera (video) toggle

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — real camera capture + ToxAV video leg + connected two-process video call; no L2 surface.
**Covered-by**: `test/ui/call/in_call_controls_real_ui_test.dart` (UI half, L1 widget-layer); `tool/mcp_test/run_fixture_c_call.sh video` (L3 two-process media leg).
**Status**: UI half covered at the widget layer (L1) — `test/ui/call/in_call_controls_real_ui_test.dart` pumps the real `CallOverlay` → `InCallView` in a VIDEO call and taps the real `UiKeys.callCameraToggleButton`, asserting the tap dispatches `toggleVideo` through the production `CallOverlayManager` interface (manager = test double delegating to the same `CallStateNotifier` mutators `CallServiceManager` calls; the real service method body stays on the 2proc gate) and the dock icon/label flip `videocam`→`videocam_off`/Video off→Video on and back (A1/A3); a second case drives the permission-gate negative (A5) where a denied camera leaves `isVideoEnabled` false and the dock unchanged. Camera capture/PiP (A3 `startCapture`, A4 preview card driven by `manager.previewListenable`) and the ToxAV video leg (A2/A3 `avMuteVideoNative`) stay L3-pinned and are exercised by `tool/mcp_test/run_fixture_c_call.sh video` (in an `inCall` video call, A `l3_call_action video`; `call.isVideoEnabled` flips; validated live 2026-06-01).

## Precondition
- A and B both online; one C2C (paired); B is a second live toxee.
- A and B in a connected video call (`CallMode.video`; `ValueKey('inCall')`, `call_overlay.dart:130`); the video dock action renders only when `isVideo` (`in_call_view.dart:194`).
- macOS Camera + Mic TCC pre-granted for `com.toxee.app`.
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; poll snapshot ≤10s for `ValueKey('call-action-dock')` (`in_call_view.dart:118`).
2. Tap the camera action via `UiKeys.callCameraToggleButton` (`call_camera_toggle_button`) to turn video OFF.
3. Poll snapshot ≤3s.
4. Tap the same action again to turn video ON; poll ≤3s.

## Assertions
- A1: after Step 2 the action shows `Icons.videocam_off` / `l10n.callVideoOn` / `selected:true` (`in_call_view.dart:195-197`).
- A2: `toggleVideo` (`call_service_manager.dart:1085`) → `muteVideo(...,true)` (`:1106`/`:1110`) → `avMuteVideoNative(...,hide=1)` (`toxav_service.dart:618`/`:621`); then `_videoHandler.stop()` (`call_service_manager.dart:1115`).
- A3: Step 4 re-checks camera permission (`requestPermissionsForCallDetailed(isVideo:true)`, `call_service_manager.dart:1088`); on grant → `muteVideo(...,hide=0)` + `startCapture` (`:1123`); A logs `[VideoHandler] macOS capture started` (`video_handler.dart:313`).
- A4: re-enabled video re-surfaces PiP `ValueKey('call-local-preview-card')` (`in_call_view.dart:402`).
- A5 (negative): if denied on Step 4, debug log `[CallServiceManager] Video permission denied while enabling camera` (`call_service_manager.dart:1094`) and `isVideoEnabled` stays false.
- A6: `official.get_runtime_errors({})` matches baseline; no `FATAL`/`bad_alloc`/`tox_kill`.

## Notes
- Control implemented (video calls only): dock → `InCallManager.toggleVideo` (`in_call_manager.dart:19`) → `CallServiceManager.toggleVideo`.
- `muteVideo` emits no log; assert via dock icon + `[VideoHandler] macOS capture started`; `selected` reflects `callState.isVideoEnabled` (`call_state_notifier.dart:39`).
- macOS has no in-app camera prompt; `[VideoHandler] ... no video devices` (`video_handler.dart:284`) = under-automation camera-gate failure.
- `CallDockAction` carries no per-action key; target by icon/label within `call-action-dock`.
- `callCameraToggleButton` is now available; remaining assertions are about media/device behavior, not locating the control.
