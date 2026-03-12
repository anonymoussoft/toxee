import 'package:flutter/foundation.dart';

class CallMediaCapabilities {
  const CallMediaCapabilities._();

  /// Speaker routing is not implemented yet, so the toggle should stay hidden
  /// instead of presenting a control that only changes local UI state.
  static bool supportsSpeakerToggle({TargetPlatform? platform}) => false;

  static bool supportsAudioRouteSelection({TargetPlatform? platform}) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return effectivePlatform == TargetPlatform.android ||
        effectivePlatform == TargetPlatform.iOS;
  }
}
