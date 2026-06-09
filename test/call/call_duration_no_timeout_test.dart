// L1 invariant gate for S70 — "call duration timeout (outgoing ring no-answer)".
// The scenario's real finding is that toxee has NO max-duration / inactivity
// auto-end: callDuration is DISPLAY-ONLY. This locks that invariant AT THE
// CallStateNotifier LAYER: a regression that adds a duration cap / auto-end
// ONTO the notifier (or breaks the increment) is caught. SCOPE: an auto-end
// wired ABOVE this layer (e.g. in CallServiceManager / the AV layer) is out of
// this test's reach — it gates the notifier's own timer semantics only.
//
// CallStateNotifier (lib/call/call_state_notifier.dart) is a zero-dependency
// ChangeNotifier; `enterCall()` starts a 1s periodic timer that only increments
// `_callDuration` (call_state_notifier.dart:114), and ONLY `endCall()` (or
// dispose) ever cancels it / leaves `inCall`. fakeAsync advances the periodic
// timer deterministically.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_state_notifier.dart';

void main() {
  // SchedulerBinding (used by the notifier's _safeNotifyListeners) needs a
  // binding; no frames are pumped under fakeAsync, so it notifies directly.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'S70: an established call never auto-ends on duration — callDuration is '
      'display-only, no max-duration/inactivity timeout', () {
    fakeAsync((async) {
      final notifier = CallStateNotifier();
      // The duration timer starts in enterCall(), NOT startRinging() — ringing
      // alone would never tick (codex).
      notifier.enterCall();
      expect(notifier.state, CallUIState.inCall);
      expect(notifier.callDuration, Duration.zero);

      // Ten minutes in: the display duration tracked it...
      async.elapse(const Duration(minutes: 10));
      expect(notifier.callDuration, const Duration(minutes: 10));
      // ...and the call is STILL active — no auto-end fired.
      expect(notifier.state, CallUIState.inCall,
          reason: 'no max-duration timeout may end an established call');

      // Two more hours: still climbing, still in-call (proves there is no cap).
      async.elapse(const Duration(hours: 2));
      expect(notifier.callDuration, const Duration(hours: 2, minutes: 10));
      expect(notifier.state, CallUIState.inCall,
          reason: 'duration is display-only; nothing auto-terminates the call');

      // Only an explicit endCall() ends it.
      notifier.endCall();
      expect(notifier.state, CallUIState.ended);

      // dispose() cancels the duration + the 2s ended-reset timers so fakeAsync
      // has no pending timers (call_state_notifier.dart:170-175).
      notifier.dispose();
    });
  });

  test('S70: startRinging alone does NOT start the duration clock', () {
    fakeAsync((async) {
      final notifier = CallStateNotifier();
      notifier.startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'inv-1',
        remoteUserID: 'peer-1',
      );
      expect(notifier.state, CallUIState.ringing);

      async.elapse(const Duration(minutes: 5));
      // No enterCall() → the periodic timer never started → duration stays 0.
      expect(notifier.callDuration, Duration.zero,
          reason: 'the duration clock is gated on enterCall(), not ringing');
      expect(notifier.state, CallUIState.ringing);

      notifier.dispose();
    });
  });
}
