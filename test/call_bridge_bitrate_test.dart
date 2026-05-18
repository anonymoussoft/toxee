// Unit tests for the bitrate-change → CallQuality mapping that powers the
// in-call quality indicator.
//
// Two layers are covered:
//   1. The pure [CallQualityEstimator] helper — threshold boundaries (≥40 →
//      good, 20–39 → medium, <20 → poor; video equivalents) and the "ignore
//      bit rate 0" rule (0 means audio/video disabled, not poor quality).
//   2. The wire-up: feeding the estimator's output into a real
//      [CallStateNotifier] via [setCallQuality]. We don't construct a full
//      CallServiceManager here (it needs an FfiChatService → libtim2tox_ffi
//      → not available in pure Dart tests); instead we simulate the same
//      call sequence the manager does.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_quality_estimator.dart';
import 'package:toxee/call/call_state_notifier.dart';

void main() {
  // CallStateNotifier.setCallQuality routes through _safeNotifyListeners,
  // which touches SchedulerBinding.instance. Initialize the test binding so
  // those notifications can land without throwing.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallQualityEstimator — audio thresholds', () {
    test('≥40 kbps → good', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(40);
      expect(e.currentQuality(), CallQuality.good);
      e.observeAudioBitrate(48);
      expect(e.currentQuality(), CallQuality.good);
      e.observeAudioBitrate(128);
      expect(e.currentQuality(), CallQuality.good);
    });

    test('20–39 kbps → medium', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(20);
      expect(e.currentQuality(), CallQuality.medium);
      e.observeAudioBitrate(30);
      expect(e.currentQuality(), CallQuality.medium);
      e.observeAudioBitrate(39);
      expect(e.currentQuality(), CallQuality.medium);
    });

    test('<20 kbps → poor', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(1);
      expect(e.currentQuality(), CallQuality.poor);
      e.observeAudioBitrate(19);
      expect(e.currentQuality(), CallQuality.poor);
    });
  });

  group('CallQualityEstimator — video thresholds', () {
    test('≥2000 kbps → good', () {
      final e = CallQualityEstimator();
      e.observeVideoBitrate(2000);
      expect(e.currentQuality(), CallQuality.good);
      e.observeVideoBitrate(5000);
      expect(e.currentQuality(), CallQuality.good);
    });

    test('500–1999 kbps → medium', () {
      final e = CallQualityEstimator();
      e.observeVideoBitrate(500);
      expect(e.currentQuality(), CallQuality.medium);
      e.observeVideoBitrate(1000);
      expect(e.currentQuality(), CallQuality.medium);
      e.observeVideoBitrate(1999);
      expect(e.currentQuality(), CallQuality.medium);
    });

    test('<500 kbps → poor', () {
      final e = CallQualityEstimator();
      e.observeVideoBitrate(100);
      expect(e.currentQuality(), CallQuality.poor);
      e.observeVideoBitrate(499);
      expect(e.currentQuality(), CallQuality.poor);
    });
  });

  group('CallQualityEstimator — bitrate 0 is ignored', () {
    test('audio 0 leaves quality unchanged and last-seen unchanged', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(48);
      expect(e.currentQuality(), CallQuality.good);
      expect(e.lastAudioBitRateForTest, 48);

      final accepted = e.observeAudioBitrate(0);
      expect(accepted, isFalse, reason: 'observeAudioBitrate(0) must reject');
      expect(e.currentQuality(), CallQuality.good,
          reason: 'quality must not change on audio=0');
      expect(e.lastAudioBitRateForTest, 48,
          reason: 'last-seen audio must not be overwritten by 0');
    });

    test('video 0 leaves quality unchanged and last-seen unchanged', () {
      final e = CallQualityEstimator();
      e.observeVideoBitrate(3000);
      expect(e.currentQuality(), CallQuality.good);

      final accepted = e.observeVideoBitrate(0);
      expect(accepted, isFalse);
      expect(e.currentQuality(), CallQuality.good);
      expect(e.lastVideoBitRateForTest, 3000);
    });

    test('audio 0 with no prior sample stays at unknown', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(0);
      expect(e.currentQuality(), CallQuality.unknown);
    });
  });

  group('CallQualityEstimator — combined quality is the worse leg', () {
    test('good audio + poor video → poor (video is the bottleneck)', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(48);
      e.observeVideoBitrate(300);
      expect(e.currentQuality(), CallQuality.poor);
    });

    test('poor audio + good video → poor (audio is the bottleneck)', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(10);
      e.observeVideoBitrate(3000);
      expect(e.currentQuality(), CallQuality.poor);
    });

    test('medium audio + good video → medium', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(30);
      e.observeVideoBitrate(3000);
      expect(e.currentQuality(), CallQuality.medium);
    });

    test('only audio known → audio quality', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(48);
      expect(e.currentQuality(), CallQuality.good);
    });

    test('only video known → video quality', () {
      final e = CallQualityEstimator();
      e.observeVideoBitrate(1000);
      expect(e.currentQuality(), CallQuality.medium);
    });
  });

  group('CallQualityEstimator — reset', () {
    test('reset clears both bitrate samples and returns to unknown', () {
      final e = CallQualityEstimator();
      e.observeAudioBitrate(48);
      e.observeVideoBitrate(3000);
      expect(e.currentQuality(), CallQuality.good);

      e.reset();
      expect(e.currentQuality(), CallQuality.unknown);
      expect(e.lastAudioBitRateForTest, isNull);
      expect(e.lastVideoBitRateForTest, isNull);
    });
  });

  group('Integration: bitrate handler → CallStateNotifier.setCallQuality',
      () {
    // Mirrors the wiring in CallServiceManager.initialize():
    //   _avService.setAudioBitrateChangedCallback(_onAudioBitrateChanged);
    //   _avService.setVideoBitrateChangedCallback(_onVideoBitrateChanged);
    // The handlers feed CallQualityEstimator and push the result into the
    // notifier. We replay that sequence here without instantiating the full
    // manager (which requires the FFI library).

    void onAudio(CallQualityEstimator e, CallStateNotifier n, int kbps) {
      if (!e.observeAudioBitrate(kbps)) return;
      n.setCallQuality(e.currentQuality());
    }

    void onVideo(CallQualityEstimator e, CallStateNotifier n, int kbps) {
      if (!e.observeVideoBitrate(kbps)) return;
      n.setCallQuality(e.currentQuality());
    }

    test('audio at 48 kbps updates notifier to good', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();
      expect(notifier.callQuality, CallQuality.unknown);

      onAudio(estimator, notifier, 48);
      expect(notifier.callQuality, CallQuality.good);
      notifier.dispose();
    });

    test('audio at 30 kbps updates notifier to medium', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();

      onAudio(estimator, notifier, 30);
      expect(notifier.callQuality, CallQuality.medium);
      notifier.dispose();
    });

    test('audio at 10 kbps updates notifier to poor', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();

      onAudio(estimator, notifier, 10);
      expect(notifier.callQuality, CallQuality.poor);
      notifier.dispose();
    });

    test('audio at 0 does NOT change notifier from prior good', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();

      onAudio(estimator, notifier, 48);
      expect(notifier.callQuality, CallQuality.good);
      onAudio(estimator, notifier, 0); // peer muted audio mid-call
      expect(notifier.callQuality, CallQuality.good,
          reason: 'audio=0 is a mute, not a quality drop');
      notifier.dispose();
    });

    test('audio at 0 with no prior sample stays unknown', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();

      onAudio(estimator, notifier, 0);
      expect(notifier.callQuality, CallQuality.unknown);
      notifier.dispose();
    });

    test('video 300 after audio 48 downgrades combined to poor', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();

      onAudio(estimator, notifier, 48);
      expect(notifier.callQuality, CallQuality.good);
      onVideo(estimator, notifier, 300);
      expect(notifier.callQuality, CallQuality.poor,
          reason: 'combined quality follows the worse leg');
      notifier.dispose();
    });

    test('notifier only fires listeners when value actually changes', () {
      final notifier = CallStateNotifier();
      final estimator = CallQualityEstimator();
      int fires = 0;
      notifier.addListener(() => fires++);

      onAudio(estimator, notifier, 48); // unknown → good
      onAudio(estimator, notifier, 50); // good → good (no-op)
      onAudio(estimator, notifier, 30); // good → medium

      expect(fires, 2,
          reason: 'CallStateNotifier.setCallQuality dedupes equal values');
      notifier.dispose();
    });
  });
}
