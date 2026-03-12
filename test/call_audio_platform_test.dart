import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_audio_platform.dart';

void main() {
  test('parses audio route state from native payload', () {
    final state = CallAudioState.fromMap({
      'sessionActive': true,
      'selectedRouteId': 'speaker',
      'routes': [
        {
          'id': 'earpiece',
          'kind': 'earpiece',
          'label': 'Earpiece',
          'selected': false,
        },
        {
          'id': 'speaker',
          'kind': 'speaker',
          'label': 'Speaker',
          'selected': true,
        },
      ],
    });

    expect(state.sessionActive, isTrue);
    expect(state.selectedRouteId, 'speaker');
    expect(state.routes, hasLength(2));
    expect(state.selectedRoute?.kind, CallAudioRouteKind.speaker);
    expect(state.canSelectRoutes, isTrue);
  });
}
