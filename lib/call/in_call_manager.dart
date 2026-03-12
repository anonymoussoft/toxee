import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'call_audio_platform.dart';

/// Minimal interface required by [InCallView]. Allows tests to supply a fake.
abstract class InCallManager {
  ValueListenable<CallAudioState> get audioState;
  ValueListenable<ui.Image?> get remoteVideo;
  Listenable get previewListenable;
  Widget? get localPreview;
  void toggleMute();
  void toggleVideo();
  void hangUp();
  Future<void> selectAudioRoute(String routeId);
}
