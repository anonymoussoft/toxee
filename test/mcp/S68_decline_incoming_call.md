# S68 — Decline incoming call

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired,both online) call=B→A(voice) mic-permission(A)=don't-care`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — two live toxees + real ToxAV reject leg; no host-bundle path injects an incoming call.
**Status**: covered by executable Fixture C call gate — `tool/mcp_test/run_fixture_c_call.sh reject` (A calls, B observes ringing, B `l3_call_action reject`; both return to `ended`/`idle`). Validated live 2026-06-01.

## Precondition
- Two instances, separate macOS Containers, distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`).
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- A↔B friends (`Prefs.local_friends_<tox>` underscore key, reciprocal), both Online before driving.
- A overlay idle: `CallStateNotifier` `idle`, bare child on `CallUIState.idle` (`call_overlay.dart:30`).
- A mic permission don't-care (reject bypasses gate — see Notes).

## Driver
1. B: place voice call to A via `UiKeys.chatCallVoiceButton` (`chat_call_voice_button`); label/icon matching remains the fallback.
2. A: poll `fmt_semantic_snapshot` ≤60s until `IncomingCallView` (`ValueKey('incoming')`, `call_overlay.dart:121`) + `CallActionDock` `incoming-call-actions` (`incoming_call_view.dart:44`) mounts.
3. A: tap reject via `UiKeys.callDeclineButton` (`call_decline_button`). Label matching remains the fallback.
4. Wait ~3s (`ended`→`idle` 2s auto-reset, `call_state_notifier.dart:128-136`), re-snapshot A.

## Assertions
- A1: incoming UI on A ≤60s — snapshot has `incoming`/`incoming-call-actions` subtree + toxB nick.
- A2: A log has `[ToxAVService] endCall: friendNumber=<n>` (`toxav_service.dart:576`) via `rejectCall`→`_avService!.endCall(fn)` (`call_service_manager.dart:985`).
- A3: A log has NO `[ToxAVService] answerCall` (`toxav_service.dart:565`) between ring and end.
- A4: `IncomingCallView` unmounts; `idle` ≤3s, bare child; `InCallView` (`ValueKey('inCall')`, `call_overlay.dart:130`) never mounted.
- A5: `onCallRecordNeeded` fires once, `endReason='reject'` (`_emitCallRecord('reject')`, `call_service_manager.dart:977`); `_callRecordEmitted` dedup.
- A6: no missed-call notification — `reject` excluded (`resolvedEndReason != 'reject'`, `call_service_manager.dart:551-553`).
- B1: B reaches `stateFinished` ≤5s (`_onCallState`, `call_service_manager.dart:619,627`); B leaves `outgoing`→`idle`, never `inCall`.
- B2: `get_runtime_errors({})` empty both sessions vs Step-0.

## Notes
- Still L3-pinned on the live twin + ToxAV reject leg, but no longer blocked: the executable Fixture C gate above covers the scenario once both instances are online.
- Remaining caveat is the real ToxAV/runtime environment itself, not control discovery.
- Contrast w/ S67: `acceptCall` gates `_ensurePermissionsForCurrentMode()` (`call_service_manager.dart:940`); `rejectCall` does not — A3/A4 hold at any A permission state.
- `[CallServiceManager]` lines are `debugPrint`-gated (debug-only); release markers are `[ToxAVService]` `_logger?.log` (A2/A3).
- `callDeclineButton` and `chatCallVoiceButton` are now available; the remaining challenge is still the real incoming-call environment rather than finding the controls.
