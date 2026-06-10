# S74 — In-call microphone mute / unmute

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — real ToxAV audio leg + connected two-process call; no L2 surface.
**Covered-by**: `test/ui/call/in_call_controls_real_ui_test.dart` (UI half, L1 widget-layer); `tool/mcp_test/run_fixture_c_call.sh voice` (L3 two-process media leg).
**Status**: UI half covered at the widget layer (L1) — `test/ui/call/in_call_controls_real_ui_test.dart` pumps the real `CallOverlay` → `InCallView` dock and taps the real `UiKeys.callMicMuteButton`, asserting the tap dispatches `toggleMute` exactly once through the production `CallOverlayManager` interface (the manager itself is a test double delegating to the same `CallStateNotifier` mutators `CallServiceManager` calls — the real service method body stays on the 2proc gate) and the dock icon/label flip `mic`→`mic_off`/Mute→Unmute and back (A1/A3) while `inCall` persists (A4). The media leg (A2 `avMuteAudioNative`) stays L3-pinned and is exercised by the Fixture C call gate `tool/mcp_test/run_fixture_c_call.sh voice` (in an `inCall` voice call, A `l3_call_action mute`; `call.isMuted` flips true; validated live 2026-06-01).

## Precondition
- A and B both online; one C2C (paired); B is a second live toxee.
- A and B in a connected voice call (`ValueKey('inCall')`, `call_overlay.dart:130`).
- macOS mic TCC pre-granted for `com.toxee.app`.
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; poll snapshot ≤10s for `ValueKey('call-action-dock')` (`in_call_view.dart:118`).
2. Tap the mute action via `UiKeys.callMicMuteButton` (`call_mic_mute_button`).
3. Poll snapshot ≤3s.
4. Tap the same action again to unmute; poll ≤3s.

## Assertions
- A1: after Step 2 the action shows `Icons.mic_off` / `l10n.callUnmute` / `selected:true` (`in_call_view.dart:188-189`).
- A2: `toggleMute` (`call_service_manager.dart:1051`) → `muteAudio(...,true)` (`:1059`/`:1066`) → `avMuteAudioNative(...,mute=1)` (`toxav_service.dart:608`/`:611`).
- A3: after Step 4 the action shows `Icons.mic` / `l10n.callMute` / `selected:false`; `avMuteAudioNative(...,mute=0)`.
- A4: `ValueKey('inCall')` present throughout; toggle does not end the call.
- A5: `official.get_runtime_errors({})` matches baseline; no `FATAL`/`bad_alloc`/`tox_kill`.

## Notes
- Control implemented: dock → `InCallManager.toggleMute` (`in_call_manager.dart:18`) → `CallServiceManager.toggleMute`.
- `muteAudio` emits no log; assert via dock icon + `get_runtime_errors`, not a string.
- `selected` reflects `callState.isMuted` (`call_state_notifier.dart:38`).
- `CallDockAction` carries no per-action key; target by icon/label within `call-action-dock`.
- `callMicMuteButton` is now available; remaining assertions are about media behavior, not control discovery.
