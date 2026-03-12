import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_effects_listener.dart';
import 'package:toxee/call/call_state_notifier.dart';

void main() {
  test('keeps screen awake while call is ringing or active', () {
    expect(
      CallWakePolicy.shouldKeepScreenAwake(CallUIState.idle),
      isFalse,
    );
    expect(
      CallWakePolicy.shouldKeepScreenAwake(CallUIState.ringing),
      isTrue,
    );
    expect(
      CallWakePolicy.shouldKeepScreenAwake(CallUIState.inCall),
      isTrue,
    );
    expect(
      CallWakePolicy.shouldKeepScreenAwake(CallUIState.ended),
      isFalse,
    );
  });
}
