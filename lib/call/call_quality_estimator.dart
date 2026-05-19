import 'call_state_notifier.dart';

/// Pure bit-rate → [CallQuality] mapper.
///
/// Lives outside [CallServiceManager] so it can be unit-tested without
/// pulling in the FFI chat service. The estimator is intentionally tiny and
/// stateless apart from the last-seen audio/video sample — callers (i.e.
/// CallServiceManager's bitrate handlers) own when to feed it, when to
/// reset, and what to do with the result.
///
/// Threshold rationale (kbit/sec):
/// - Audio: ≥40 = good, 20–39 = medium, <20 = poor. c-toxcore's default
///   audio bit rate is 48 kbit/sec; healthy calls stay above 40, and
///   congestion-throttled audio drops to ~16–24 in practice.
/// - Video: ≥2000 = good, 500–1999 = medium, <500 = poor. c-toxcore's
///   default video start rate is 5 Mbit/sec; aggressive congestion drops
///   it toward ~300–500.
///
/// Bit rate `0` is **not** a quality signal — it means the peer disabled
/// audio or video. Feed it via [observeAudioBitrate] / [observeVideoBitrate]
/// and the estimator will return its current quality unchanged.
class CallQualityEstimator {
  static const int audioBitrateGood = 40;
  static const int audioBitrateMedium = 20;
  static const int videoBitrateGood = 2000;
  static const int videoBitrateMedium = 500;

  int? _lastAudioBitRate;
  int? _lastVideoBitRate;

  int? get lastAudioBitRateForTest => _lastAudioBitRate;
  int? get lastVideoBitRateForTest => _lastVideoBitRate;

  /// Record an audio bitrate sample. Returns `true` if the sample was
  /// accepted (i.e. non-zero); `false` if it was ignored as "media disabled".
  bool observeAudioBitrate(int kbps) {
    if (kbps == 0) return false;
    _lastAudioBitRate = kbps;
    return true;
  }

  /// Record a video bitrate sample. See [observeAudioBitrate] for the
  /// zero-is-disabled rule.
  bool observeVideoBitrate(int kbps) {
    if (kbps == 0) return false;
    _lastVideoBitRate = kbps;
    return true;
  }

  /// Reset both bitrate samples (e.g. on call end).
  void reset() {
    _lastAudioBitRate = null;
    _lastVideoBitRate = null;
  }

  /// Compute the combined call quality from the last-seen audio + video
  /// bitrate samples. Combined quality is the *worse* of the two known
  /// legs — a glorious video stream means nothing if the audio is choppy,
  /// and vice versa.
  CallQuality currentQuality() {
    final a = _audioBitrateToQuality(_lastAudioBitRate);
    final v = _videoBitrateToQuality(_lastVideoBitRate);
    if (a == null && v == null) return CallQuality.unknown;
    if (a == null) return v!;
    if (v == null) return a;
    return _worseQuality(a, v);
  }

  static CallQuality? _audioBitrateToQuality(int? kbps) {
    if (kbps == null) return null;
    if (kbps >= audioBitrateGood) return CallQuality.good;
    if (kbps >= audioBitrateMedium) return CallQuality.medium;
    return CallQuality.poor;
  }

  static CallQuality? _videoBitrateToQuality(int? kbps) {
    if (kbps == null) return null;
    if (kbps >= videoBitrateGood) return CallQuality.good;
    if (kbps >= videoBitrateMedium) return CallQuality.medium;
    return CallQuality.poor;
  }

  static CallQuality _worseQuality(CallQuality a, CallQuality b) {
    int rank(CallQuality q) => switch (q) {
          CallQuality.good => 3,
          CallQuality.medium => 2,
          CallQuality.poor => 1,
          CallQuality.unknown => 0,
        };
    return rank(a) <= rank(b) ? a : b;
  }
}
