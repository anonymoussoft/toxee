import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_codec_profile.dart';

void main() {
  group('CallCodecProfile defaults', () {
    test('default profile is mid tier (48k audio / 2M video / 15fps)', () {
      const p = CallCodecProfile.defaultProfile;
      expect(p.tier, CallCodecTier.mid);
      expect(p.audioBitRate, 48);
      expect(p.videoBitRate, 2000);
      expect(p.videoFps, 15);
    });

    test('audioOnly() zeros video target without touching audio', () {
      final p = CallCodecProfile.high.audioOnly();
      expect(p.audioBitRate, 64);
      expect(p.videoBitRate, 0);
      expect(p.videoFps, 0);
      expect(p.minFrameInterval, Duration.zero);
    });

    test('minFrameInterval matches FPS', () {
      expect(CallCodecProfile.low.minFrameInterval,
          const Duration(microseconds: 83333));
      expect(CallCodecProfile.mid.minFrameInterval,
          const Duration(microseconds: 66666));
      expect(CallCodecProfile.high.minFrameInterval,
          const Duration(microseconds: 33333));
    });
  });

  group('CallCodecProfile.fromAudioBitRate', () {
    test('null on 0 or negative (peer disabled audio)', () {
      expect(CallCodecProfile.fromAudioBitRate(0), isNull);
      expect(CallCodecProfile.fromAudioBitRate(-5), isNull);
    });

    test('thresholds: ≥56 high, ≥32 mid, else low', () {
      expect(CallCodecProfile.fromAudioBitRate(64)?.tier, CallCodecTier.high);
      expect(CallCodecProfile.fromAudioBitRate(56)?.tier, CallCodecTier.high);
      expect(CallCodecProfile.fromAudioBitRate(48)?.tier, CallCodecTier.mid);
      expect(CallCodecProfile.fromAudioBitRate(32)?.tier, CallCodecTier.mid);
      expect(CallCodecProfile.fromAudioBitRate(24)?.tier, CallCodecTier.low);
      expect(CallCodecProfile.fromAudioBitRate(8)?.tier, CallCodecTier.low);
    });
  });

  group('CallCodecProfile.fromVideoBitRate', () {
    test('null on 0 (audio-only)', () {
      expect(CallCodecProfile.fromVideoBitRate(0), isNull);
      expect(CallCodecProfile.fromVideoBitRate(-100), isNull);
    });

    test('thresholds: ≥3000 high, ≥1200 mid, else low', () {
      expect(CallCodecProfile.fromVideoBitRate(5000)?.tier, CallCodecTier.high);
      expect(CallCodecProfile.fromVideoBitRate(3000)?.tier, CallCodecTier.high);
      expect(CallCodecProfile.fromVideoBitRate(2000)?.tier, CallCodecTier.mid);
      expect(CallCodecProfile.fromVideoBitRate(1200)?.tier, CallCodecTier.mid);
      expect(CallCodecProfile.fromVideoBitRate(800)?.tier, CallCodecTier.low);
      expect(CallCodecProfile.fromVideoBitRate(100)?.tier, CallCodecTier.low);
    });
  });

  test('equality is by-value', () {
    expect(CallCodecProfile.mid, equals(CallCodecProfile.defaultProfile));
    expect(CallCodecProfile.high, isNot(equals(CallCodecProfile.low)));
  });
}
