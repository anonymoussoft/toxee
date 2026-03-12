import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class TransformedI420Frame {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int width;
  final int height;

  const TransformedI420Frame({
    required this.y,
    required this.u,
    required this.v,
    required this.width,
    required this.height,
  });
}

class OutgoingVideoTransform {
  final int quarterTurns;
  final bool shouldMirror;

  const OutgoingVideoTransform({
    required this.quarterTurns,
    required this.shouldMirror,
  });

  static OutgoingVideoTransform compute({
    required TargetPlatform platform,
    required DeviceOrientation deviceOrientation,
    required CameraDescription camera,
  }) {
    if (platform != TargetPlatform.android) {
      return const OutgoingVideoTransform(
        quarterTurns: 0,
        shouldMirror: false,
      );
    }

    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final rotationDegrees = switch (camera.lensDirection) {
      CameraLensDirection.front =>
        (camera.sensorOrientation + deviceDegrees) % 360,
      _ => (camera.sensorOrientation - deviceDegrees + 360) % 360,
    };

    return OutgoingVideoTransform(
      quarterTurns: rotationDegrees ~/ 90,
      shouldMirror: false,
    );
  }
}

class I420FrameTransformer {
  const I420FrameTransformer._();

  static TransformedI420Frame apply({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int quarterTurns,
  }) {
    final normalizedQuarterTurns = quarterTurns % 4;
    if (normalizedQuarterTurns == 0) {
      return TransformedI420Frame(
        y: y,
        u: u,
        v: v,
        width: width,
        height: height,
      );
    }

    final rotatedY = _rotatePlane(
      plane: y,
      width: width,
      height: height,
      quarterTurns: normalizedQuarterTurns,
    );
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final rotatedU = _rotatePlane(
      plane: u,
      width: chromaWidth,
      height: chromaHeight,
      quarterTurns: normalizedQuarterTurns,
    );
    final rotatedV = _rotatePlane(
      plane: v,
      width: chromaWidth,
      height: chromaHeight,
      quarterTurns: normalizedQuarterTurns,
    );

    return TransformedI420Frame(
      y: rotatedY,
      u: rotatedU,
      v: rotatedV,
      width: normalizedQuarterTurns.isOdd ? height : width,
      height: normalizedQuarterTurns.isOdd ? width : height,
    );
  }

  static Uint8List _rotatePlane({
    required Uint8List plane,
    required int width,
    required int height,
    required int quarterTurns,
  }) {
    final output = Uint8List((quarterTurns.isOdd ? height : width) *
        (quarterTurns.isOdd ? width : height));
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sourceIndex = row * width + col;
        late final int destRow;
        late final int destCol;
        switch (quarterTurns) {
          case 1:
            destRow = col;
            destCol = height - row - 1;
            break;
          case 2:
            destRow = height - row - 1;
            destCol = width - col - 1;
            break;
          case 3:
            destRow = width - col - 1;
            destCol = row;
            break;
          default:
            destRow = row;
            destCol = col;
            break;
        }
        final destWidth = quarterTurns.isOdd ? height : width;
        final destIndex = destRow * destWidth + destCol;
        output[destIndex] = plane[sourceIndex];
      }
    }
    return output;
  }
}
