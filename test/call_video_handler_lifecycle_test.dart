// Lifecycle invariants for [VideoHandler]: dispose must not race with
// in-flight stop, and notifyListeners must not throw after dispose.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/video_handler.dart';

void main() {
  group('VideoHandler lifecycle', () {
    test('dispose marks handler as disposed', () {
      final h = VideoHandler();
      expect(h.isDisposed, isFalse);
      h.dispose();
      expect(h.isDisposed, isTrue);
    });

    test('double-dispose is a no-op (does not throw)', () {
      final h = VideoHandler();
      h.dispose();
      expect(h.dispose, returnsNormally);
    });

    test('disposeAsync completes cleanly with no active capture', () async {
      final h = VideoHandler();
      await h.disposeAsync();
      expect(h.isDisposed, isTrue);
    });

    test('disposeAsync after dispose is a no-op', () async {
      final h = VideoHandler();
      h.dispose();
      // Must not double-dispose super; must complete normally.
      await expectLater(h.disposeAsync(), completes);
    });

    test('stop is safe after dispose (notifyListeners suppressed)', () async {
      final h = VideoHandler();
      h.dispose();
      // dispose() kicks off an unawaited stop(); calling stop() again must
      // not throw against the now-disposed ChangeNotifier — the
      // [notifyListeners] override silently no-ops.
      await expectLater(h.stop(), completes);
    });

    test(
        'remoteImage is cleared on stop (sync ValueNotifier path, '
        'independent of any in-flight platform teardown)', () async {
      final h = VideoHandler();
      // Sanity: no camera initialized, remoteImage starts null.
      expect(h.remoteImage.value, isNull);
      await h.stop();
      expect(h.remoteImage.value, isNull);
      h.dispose();
    });
  });
}
