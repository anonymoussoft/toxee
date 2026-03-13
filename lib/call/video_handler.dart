import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';

import '../util/logger.dart';
import 'call_video_transform.dart';

class VideoPlaneData {
  final List<int> bytes;
  final int bytesPerRow;
  final int bytesPerPixel;

  const VideoPlaneData({
    required this.bytes,
    required this.bytesPerRow,
    int? bytesPerPixel,
  }) : bytesPerPixel = bytesPerPixel ?? 1;
}

class NormalizedVideoFrame {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;

  const NormalizedVideoFrame({
    required this.y,
    required this.u,
    required this.v,
  });
}

class VideoFrameNormalizer {
  const VideoFrameNormalizer._();

  static NormalizedVideoFrame normalizeYuv420({
    required int width,
    required int height,
    required List<VideoPlaneData> planes,
  }) {
    if (planes.length == 3) {
      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      return NormalizedVideoFrame(
        y: _compactPlane(
          plane: planes[0],
          width: width,
          height: height,
        ),
        u: _compactPlane(
          plane: planes[1],
          width: uvWidth,
          height: uvHeight,
        ),
        v: _compactPlane(
          plane: planes[2],
          width: uvWidth,
          height: uvHeight,
        ),
      );
    }

    if (planes.length == 2) {
      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      final y = _compactPlane(
        plane: planes[0],
        width: width,
        height: height,
      );
      final uvPlane = planes[1];
      final u = Uint8List(uvWidth * uvHeight);
      final v = Uint8List(uvWidth * uvHeight);
      var index = 0;

      for (var row = 0; row < uvHeight; row++) {
        final rowStart = row * uvPlane.bytesPerRow;
        for (var col = 0; col < uvWidth; col++) {
          final offset = rowStart + (col * 2);
          if (offset + 1 >= uvPlane.bytes.length) {
            throw RangeError(
              'UV plane buffer is too small for $width x $height frame',
            );
          }
          u[index] = uvPlane.bytes[offset];
          v[index] = uvPlane.bytes[offset + 1];
          index++;
        }
      }

      return NormalizedVideoFrame(y: y, u: u, v: v);
    }

    throw UnsupportedError(
      'Unsupported YUV420 plane layout: ${planes.length} planes',
    );
  }

  static Uint8List _compactPlane({
    required VideoPlaneData plane,
    required int width,
    required int height,
  }) {
    final output = Uint8List(width * height);
    final pixelStride = plane.bytesPerPixel <= 0 ? 1 : plane.bytesPerPixel;
    var index = 0;

    for (var row = 0; row < height; row++) {
      final rowStart = row * plane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        final offset = rowStart + (col * pixelStride);
        if (offset >= plane.bytes.length) {
          throw RangeError(
            'Plane buffer is too small for $width x $height plane',
          );
        }
        output[index++] = plane.bytes[offset];
      }
    }

    return output;
  }
}

/// Data class to pass YUV420 frame data to an Isolate via compute().
class _Yuv420Frame {
  final int width;
  final int height;
  final List<int> y;
  final List<int> u;
  final List<int> v;

  _Yuv420Frame(this.width, this.height, this.y, this.u, this.v);
}

/// Top-level function: convert YUV420 to RGBA in an Isolate.
/// Must be top-level (not a closure/method) for compute() to work.
Uint8List _convertYuv420ToRgba(_Yuv420Frame frame) {
  final width = frame.width;
  final height = frame.height;
  final y = frame.y;
  final u = frame.u;
  final v = frame.v;
  final uvWidth = width ~/ 2;
  final rgba = Uint8List(width * height * 4);

  for (int row = 0; row < height; row++) {
    final rowOffset = row * width;
    final uvRowOffset = (row ~/ 2) * uvWidth;
    for (int col = 0; col < width; col++) {
      final yVal = y[rowOffset + col].toDouble();
      final uvCol = col ~/ 2;
      final uVal = u[uvRowOffset + uvCol].toDouble() - 128;
      final vVal = v[uvRowOffset + uvCol].toDouble() - 128;
      final r = (yVal + 1.402 * vVal).clamp(0.0, 255.0).toInt();
      final g = (yVal - 0.344 * uVal - 0.714 * vVal).clamp(0.0, 255.0).toInt();
      final b = (yVal + 1.772 * uVal).clamp(0.0, 255.0).toInt();
      final i = (rowOffset + col) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

/// Video capture (camera → YUV420 → ToxAV) and receive (YUV420 → display).
/// Extends ChangeNotifier so UI can react to camera initialization.
class VideoHandler extends ChangeNotifier {
  ToxAVService? _avService;
  int _friendNumber = 0;
  bool _capturing = false;
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;

  /// macOS-only: when using camera_macos (official camera plugin has no macOS impl).
  bool _usingMacOSCamera = false;
  int? _macosTextureId;

  /// Throttle: skip frames to reduce CPU/bandwidth usage (~15fps max).
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minFrameInterval = Duration(milliseconds: 66); // ~15fps

  /// Guard against overlapping compute() calls.
  bool _converting = false;

  /// Latest remote frame as RGB for display. UI can listen and show via RawImage.
  final ValueNotifier<ui.Image?> remoteImage = ValueNotifier<ui.Image?>(null);

  /// Whether the local camera preview is ready.
  bool get isLocalPreviewReady =>
      (_controller != null && _controller!.value.isInitialized) ||
      (_usingMacOSCamera && _macosTextureId != null);

  /// Start camera capture and send YUV420 frames to ToxAV.
  /// On macOS uses [camera_macos] (official camera plugin has no macOS impl);
  /// that triggers the system camera permission dialog and provides the stream.
  Future<void> startCapture(int friendNumber, ToxAVService avService) async {
    if (_capturing) return;
    _friendNumber = friendNumber;
    _avService = avService;
    _capturing = true;

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        final devices = await CameraMacOS.instance
            .listDevices(deviceType: CameraMacOSDeviceType.video);
        if (devices.isEmpty) {
          _capturing = false;
          notifyListeners();
          debugPrint(
              '[VideoHandler] startCapture macOS: no video devices. '
              'Allow Camera in System Settings → Privacy & Security.');
          AppLogger.log(
              '[VideoHandler] startCapture macOS: no video devices (check Camera permission)');
          return;
        }
        final deviceId =
            devices[_cameraIndex % devices.length].deviceId;
        final args = await CameraMacOS.instance.initialize(
          deviceId: deviceId,
          cameraMacOSMode: CameraMacOSMode.video,
        );
        if (args == null) {
          throw StateError('camera_macos initialize returned null');
        }
        final textureId = args.textureId;
        if (textureId == null) {
          throw StateError('camera_macos initialize returned null textureId');
        }
        _macosTextureId = textureId;
        _usingMacOSCamera = true;
        notifyListeners();
        await CameraMacOS.instance.startImageStream(
          (CameraImageData? data) {
            if (data != null) _onMacOSCameraImage(data);
          },
          onError: (e) {
            debugPrint('[VideoHandler] macOS image stream error: $e');
            AppLogger.log('[VideoHandler] macOS image stream error: $e');
          },
        );
        AppLogger.log(
            '[VideoHandler] macOS capture started (camera_macos stream active)');
      } catch (e) {
        _capturing = false;
        _usingMacOSCamera = false;
        _macosTextureId = null;
        notifyListeners();
        debugPrint('[VideoHandler] startCapture macOS camera_macos error: $e');
        AppLogger.log('[VideoHandler] startCapture macOS camera_macos error: $e');
        debugPrint(
            '[VideoHandler] On macOS: ensure Camera is allowed in '
            'System Settings → Privacy & Security.');
        AppLogger.log(
            '[VideoHandler] On macOS: ensure Camera is allowed in '
            'System Settings → Privacy & Security.');
      }
      return;
    }

    try {
      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _capturing = false;
        notifyListeners();
        debugPrint(
            '[VideoHandler] startCapture: no cameras available. '
            'On macOS: allow Camera in System Settings → Privacy & Security, '
            'and close other apps using the camera.');
        return;
      }
      final camera = _cameras![_cameraIndex % _cameras!.length];
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      notifyListeners();
      await _controller!.startImageStream(_onCameraImage);
      AppLogger.log('[VideoHandler] capture started (camera stream active)');
    } on MissingPluginException catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint(
          '[VideoHandler] startCapture: camera plugin not implemented on this '
          'platform, local preview disabled: $e');
      AppLogger.log(
          '[VideoHandler] startCapture: camera plugin not implemented: $e');
    } catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint('[VideoHandler] startCapture error: $e');
      AppLogger.log('[VideoHandler] startCapture error: $e');
    }
  }

  /// Handles frames from camera_macos (ARGB8888) on macOS; converts to YUV and sends.
  void _onMacOSCameraImage(CameraImageData data) {
    if (!_capturing || _avService == null) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    try {
      final converted = RgbToYuv420.argb8888ToYuv420(
        argb: data.bytes,
        width: data.width,
        height: data.height,
        bytesPerRow: data.bytesPerRow,
      );
      const quarterTurns = 0;
      final transformedFrame = I420FrameTransformer.apply(
        y: converted.y,
        u: converted.u,
        v: converted.v,
        width: data.width,
        height: data.height,
        quarterTurns: quarterTurns,
      );
      _avService!.sendVideoFrame(
        _friendNumber,
        transformedFrame.width,
        transformedFrame.height,
        transformedFrame.y,
        transformedFrame.u,
        transformedFrame.v,
        yStride: transformedFrame.width,
        uStride: transformedFrame.width ~/ 2,
        vStride: transformedFrame.width ~/ 2,
      );
    } catch (e) {
      debugPrint('[VideoHandler] _onMacOSCameraImage error: $e');
    }
  }

  void _onCameraImage(CameraImage image) {
    if (!_capturing || _avService == null) return;

    // Frame rate throttle
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    try {
      NormalizedVideoFrame normalized;
      final int width = image.width;
      final int height = image.height;

      if (image.format.group == ImageFormatGroup.bgra8888 &&
          image.planes.isNotEmpty) {
        final plane = image.planes[0];
        final converted = RgbToYuv420.bgra8888ToYuv420(
          bgra: plane.bytes,
          width: width,
          height: height,
          bytesPerRow: plane.bytesPerRow,
        );
        normalized = NormalizedVideoFrame(
          y: converted.y,
          u: converted.u,
          v: converted.v,
        );
      } else if (image.format.group == ImageFormatGroup.yuv420 &&
          image.planes.length >= 2) {
        final planes = image.planes.asMap().entries.map((entry) {
          final plane = entry.value;
          final isBiPlanarUv = image.planes.length == 2 && entry.key == 1;
          return VideoPlaneData(
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel ?? (isBiPlanarUv ? 2 : 1),
          );
        }).toList();
        normalized = VideoFrameNormalizer.normalizeYuv420(
          width: width,
          height: height,
          planes: planes,
        );
      } else {
        return;
      }

      final deviceOrientation =
          _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp;
      final outgoingTransform = OutgoingVideoTransform.compute(
        platform: defaultTargetPlatform,
        deviceOrientation: deviceOrientation,
        camera: _cameras![_cameraIndex % _cameras!.length],
      );
      final transformedFrame = I420FrameTransformer.apply(
        y: normalized.y,
        u: normalized.u,
        v: normalized.v,
        width: width,
        height: height,
        quarterTurns: outgoingTransform.quarterTurns,
      );
      _avService!.sendVideoFrame(
        _friendNumber,
        transformedFrame.width,
        transformedFrame.height,
        transformedFrame.y,
        transformedFrame.u,
        transformedFrame.v,
        yStride: transformedFrame.width,
        uStride: transformedFrame.width ~/ 2,
        vStride: transformedFrame.width ~/ 2,
      );
    } catch (e) {
      debugPrint('[VideoHandler] normalize/send frame error: $e');
    }
  }

  /// Called when ToxAV receives a video frame (YUV420).
  /// Converts to RGBA in an Isolate via compute(), then updates [remoteImage].
  void onVideoReceived(int friendNumber, int width, int height, List<int> y,
      List<int> u, List<int> v) {
    if (width <= 0 || height <= 0 || y.length < width * height) return;
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    if (u.length < uvWidth * uvHeight || v.length < uvWidth * uvHeight) return;

    // Skip if a previous conversion is still running
    if (_converting) return;
    _converting = true;

    final frame = _Yuv420Frame(width, height, y, u, v);
    compute(_convertYuv420ToRgba, frame).then((rgba) {
      _converting = false;
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          final previous = remoteImage.value;
          remoteImage.value = image;
          previous?.dispose();
        },
        rowBytes: width * 4,
      );
    }).catchError((e) {
      _converting = false;
      debugPrint('[VideoHandler] compute error: $e');
    });
  }

  /// Local camera preview widget.
  Widget? get localPreview {
    if (_usingMacOSCamera && _macosTextureId != null) {
      return Texture(textureId: _macosTextureId!);
    }
    if (_controller == null || !_controller!.value.isInitialized) return null;
    return CameraPreview(_controller!);
  }

  Future<void> stop() async {
    _capturing = false;
    if (_usingMacOSCamera) {
      try {
        await CameraMacOS.instance.stopImageStream();
        await CameraMacOS.instance.destroy();
      } catch (_) {}
      _usingMacOSCamera = false;
      _macosTextureId = null;
    }
    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    final previous = remoteImage.value;
    remoteImage.value = null;
    previous?.dispose();
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    final wasCapturing = _capturing;
    await stop();
    _cameraIndex++;
    if (wasCapturing && _avService != null) {
      await startCapture(_friendNumber, _avService!);
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
