/// Audio/video bit-rate + frame-rate profile picked by the call layer when
/// initialising a ToxAV stream and adapted at runtime in response to
/// peer-signalled bandwidth changes (via the ToxAV bitrate callbacks).
///
/// The previous implementation hardcoded `audioBitRate: 48` and
/// `videoBitRate: 5000` (kbit/s) at five different call sites
/// (`CallServiceManager.acceptCall`, `TUICallKitAdapter._handleCall`,
/// `VideoHandler._minFrameInterval`, plus the in-call view's video toggle).
/// That's wrong on two axes:
///
///   1. Identical values for every device/network meant a slow connection
///      saw the same 5 Mbit/s video target as a fast one, fell over, and
///      stayed fallen over because nothing reduced the target.
///   2. No way for the peer-suggested bitrate callbacks (newly wired in
///      [ToxAVService]) to influence what the local encoder produces.
///
/// This enum is the single source of truth. Higher tiers are spent
/// optimistically; downgrades happen when the peer signals it's receiving
/// less than we're sending or the codec layer asks us to slow down.
///
/// Threshold values are deliberately conservative — toxav's encoder can
/// fall back further than these targets internally, so we want the *upper*
/// bound to be reachable on a fair link, not the *lower* bound to be the
/// floor.
library;

import 'package:flutter/foundation.dart';

enum CallCodecTier {
  /// 24 kbps audio, 800 kbps video at ~12fps. Edge / weak Wi-Fi.
  low,

  /// 48 kbps audio, 2000 kbps video at ~15fps. Default; healthy 4G or
  /// home Wi-Fi.
  mid,

  /// 64 kbps audio, 5000 kbps video at ~30fps. Wired/strong Wi-Fi only;
  /// only reached after a successful initial probe.
  high,
}

@immutable
class CallCodecProfile {
  /// Audio bit-rate target in kbit/s.
  final int audioBitRate;

  /// Video bit-rate target in kbit/s. Use 0 when video is disabled for
  /// this call.
  final int videoBitRate;

  /// Camera capture / encode frame rate cap. Used by [VideoHandler] to
  /// throttle frames sent to the encoder.
  final int videoFps;

  final CallCodecTier tier;

  const CallCodecProfile({
    required this.audioBitRate,
    required this.videoBitRate,
    required this.videoFps,
    required this.tier,
  });

  /// Minimum frame interval at this tier's video FPS.
  Duration get minFrameInterval =>
      videoFps <= 0 ? Duration.zero : Duration(microseconds: 1000000 ~/ videoFps);

  /// The default we pick before any peer signal has arrived. Mid is
  /// optimistic but reachable; observed bitrate callbacks will move us up
  /// or down from here.
  static const CallCodecProfile defaultProfile = CallCodecProfile(
    audioBitRate: 48,
    videoBitRate: 2000,
    videoFps: 15,
    tier: CallCodecTier.mid,
  );

  static const CallCodecProfile low = CallCodecProfile(
    audioBitRate: 24,
    videoBitRate: 800,
    videoFps: 12,
    tier: CallCodecTier.low,
  );

  static const CallCodecProfile mid = defaultProfile;

  static const CallCodecProfile high = CallCodecProfile(
    audioBitRate: 64,
    videoBitRate: 5000,
    videoFps: 30,
    tier: CallCodecTier.high,
  );

  /// Audio-only variant — clamps the video target to 0 so the encoder
  /// doesn't allocate a video stream at all.
  CallCodecProfile audioOnly() => CallCodecProfile(
        audioBitRate: audioBitRate,
        videoBitRate: 0,
        videoFps: 0,
        tier: tier,
      );

  /// Pick a profile from a peer-suggested audio bitrate. Used by the
  /// `toxav_audio_bit_rate_cb` handler to map a kbit/s value to the
  /// nearest standard tier so the local encoder follows.
  ///
  /// Returns `null` if [audioBitRate] is 0 (peer disabled audio).
  static CallCodecProfile? fromAudioBitRate(int audioBitRate) {
    if (audioBitRate <= 0) return null;
    if (audioBitRate >= 56) return high;
    if (audioBitRate >= 32) return mid;
    return low;
  }

  /// Pick a profile from a peer-suggested video bitrate. Returns `null`
  /// when [videoBitRate] is 0 (peer disabled video / audio-only).
  static CallCodecProfile? fromVideoBitRate(int videoBitRate) {
    if (videoBitRate <= 0) return null;
    if (videoBitRate >= 3000) return high;
    if (videoBitRate >= 1200) return mid;
    return low;
  }

  @override
  String toString() =>
      'CallCodecProfile(tier=$tier audio=${audioBitRate}kbps video=${videoBitRate}kbps fps=$videoFps)';

  @override
  bool operator ==(Object other) =>
      other is CallCodecProfile &&
      other.audioBitRate == audioBitRate &&
      other.videoBitRate == videoBitRate &&
      other.videoFps == videoFps &&
      other.tier == tier;

  @override
  int get hashCode =>
      Object.hash(audioBitRate, videoBitRate, videoFps, tier);
}
