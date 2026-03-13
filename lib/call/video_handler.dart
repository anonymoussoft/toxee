import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';
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

  /// Throttle: skip frames to reduce CPU/bandwidth usage (~15fps max).
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minFrameInterval = Duration(milliseconds: 66); // ~15fps

  /// Guard against overlapping compute() calls.
  bool _converting = false;

  /// Latest remote frame as RGB for display. UI can listen and show via RawImage.
  final ValueNotifier<ui.Image?> remoteImage = ValueNotifier<ui.Image?>(null);

  /// Whether the local camera preview is ready.
  bool get isLocalPreviewReady =>
      _controller != null && _controller!.value.isInitialized;

  /// Start camera capture and send YUV420 frames to ToxAV.
  /// On platforms where the camera plugin is not implemented (e.g. macOS desktop),
  /// catches [MissingPluginException], leaves local preview empty but allows
  /// the call UI and remote video to work.
  Future<void> startCapture(int friendNumber, ToxAVService avService) async {
    if (_capturing) return;
    _friendNumber = friendNumber;
    _avService = avService;
    _capturing = true;
    try {
      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _capturing = false;
        notifyListeners();
        debugPrint(
            '[VideoHandler] startCapture: no cameras available (e.g. desktop)');
        return;
      }
      final camera = _cameras![_cameraIndex % _cameras!.length];
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      notifyListeners(); // Notify UI that local preview is ready
      await _controller!.startImageStream(_onCameraImage);
    } on MissingPluginException catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint(
          '[VideoHandler] startCapture: camera plugin not implemented on this '
          'platform (e.g. macOS), local preview disabled: $e');
    } catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint('[VideoHandler] startCapture error: $e');
    }
  }

  void _onCameraImage(CameraImage image) {
    if (!_capturing || _avService == null || image.planes.length < 2) return;
    if (image.format.group != ImageFormatGroup.yuv420) return;

    // Frame rate throttle
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    try {
      final planes = image.planes.asMap().entries.map((entry) {
        final plane = entry.value;
        final isBiPlanarUv = image.planes.length == 2 && entry.key == 1;
        return VideoPlaneData(
          bytes: plane.bytes,
          bytesPerRow: plane.bytesPerRow,
          bytesPerPixel: plane.bytesPerPixel ?? (isBiPlanarUv ? 2 : 1),
        );
      }).toList();
      final normalized = VideoFrameNormalizer.normalizeYuv420(
        width: image.width,
        height: image.height,
        planes: planes,
      );
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
        width: image.width,
        height: image.height,
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
    if (_controller == null || !_controller!.value.isInitialized) return null;
    return CameraPreview(_controller!);
  }

  Future<void> stop() async {
    _capturing = false;
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
