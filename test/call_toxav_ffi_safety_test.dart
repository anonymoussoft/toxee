// Verifies the FFI-safety invariant of `ToxAVService` receive trampolines:
// the audio/video buffers handed to user callbacks must be Dart-owned copies,
// fully decoupled from the c-toxcore-owned source pointers (which are recycled
// after the trampoline returns).
//
// Regression scope:
//   - Previously, `_onAudioReceiveNativeTrampoline` and
//     `_onVideoReceiveNativeTrampoline` passed `Pointer.asTypedList(...)`
//     views directly to consumers. If a consumer iterated the view
//     asynchronously (e.g. inside a `compute()` isolate, or after an `await`),
//     and c-toxcore recycled the buffer in the meantime, the consumer read
//     freed/overwritten memory.
//   - This test allocates a native buffer, runs the copy helper, mutates
//     the source pointer, and asserts the copy still reflects the original
//     contents.

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';

void main() {
  group('ToxAVService FFI safety — copyAudioForCallback', () {
    test('mono: copies sampleCount samples, decoupled from source pointer',
        () {
      const sampleCount = 960; // 20 ms @ 48 kHz
      final ptr = pkgffi.malloc<ffi.Int16>(sampleCount);
      try {
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = (i * 7) & 0x7FFF;
        }

        final copy = ToxAVService.copyAudioForCallback(ptr, sampleCount, 1);
        expect(copy.length, sampleCount);
        expect(copy[0], 0);
        expect(copy[1], 7);
        expect(copy[100], (700) & 0x7FFF);

        // Mutate source pointer; the copy must remain intact.
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = 0;
        }
        expect(copy[0], 0); // coincidence
        expect(copy[1], 7); // proves copy is decoupled
        expect(copy[100], (700) & 0x7FFF);
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });

    test('stereo: copies sampleCount * channels (interleaved L/R)', () {
      const sampleCount = 480; // per-channel
      const channels = 2;
      final total = sampleCount * channels;
      final ptr = pkgffi.malloc<ffi.Int16>(total);
      try {
        // Distinguishable L/R pattern: L = +i, R = -i
        for (var i = 0; i < sampleCount; i++) {
          ptr[i * 2] = i;
          ptr[i * 2 + 1] = -i;
        }

        final copy =
            ToxAVService.copyAudioForCallback(ptr, sampleCount, channels);
        expect(copy.length, total,
            reason:
                'sampleCount is per-channel; total samples = sampleCount * channels '
                '(matches libtoxav toxav_audio_receive_frame_cb contract)');
        expect(copy[0], 0);
        expect(copy[1], 0);
        expect(copy[2], 1);
        expect(copy[3], -1);
        expect(copy[total - 2], sampleCount - 1);
        expect(copy[total - 1], -(sampleCount - 1));
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });

    test('channels <= 0 defensively treated as mono (defends against 0)', () {
      const sampleCount = 16;
      final ptr = pkgffi.malloc<ffi.Int16>(sampleCount);
      try {
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = i + 1;
        }
        final copy = ToxAVService.copyAudioForCallback(ptr, sampleCount, 0);
        expect(copy.length, sampleCount);
        expect(copy.last, sampleCount);
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });
  });

  group('ToxAVService FFI safety — copyVideoForCallback', () {
    test('I420 planes: y is w*h, u/v are (w/2)*(h/2), all decoupled', () {
      const width = 64;
      const height = 48;
      final ySize = width * height;
      final uvSize = (width ~/ 2) * (height ~/ 2);

      final yPtr = pkgffi.malloc<ffi.Uint8>(ySize);
      final uPtr = pkgffi.malloc<ffi.Uint8>(uvSize);
      final vPtr = pkgffi.malloc<ffi.Uint8>(uvSize);
      try {
        for (var i = 0; i < ySize; i++) {
          yPtr[i] = (i & 0xFF);
        }
        for (var i = 0; i < uvSize; i++) {
          uPtr[i] = (i & 0xFF) ^ 0x55;
          vPtr[i] = (i & 0xFF) ^ 0xAA;
        }

        final (yCopy, uCopy, vCopy) =
            ToxAVService.copyVideoForCallback(width, height, yPtr, uPtr, vPtr);

        expect(yCopy, isA<Uint8List>());
        expect(yCopy.length, ySize);
        expect(uCopy.length, uvSize);
        expect(vCopy.length, uvSize);

        // Spot-check content against the deterministic pattern above.
        expect(yCopy[0], 0);
        expect(yCopy[1], 1);
        expect(yCopy[ySize - 1], (ySize - 1) & 0xFF);
        expect(uCopy[0], 0x55);
        expect(vCopy[0], 0xAA);
        expect(uCopy[uvSize - 1], ((uvSize - 1) & 0xFF) ^ 0x55);
        expect(vCopy[uvSize - 1], ((uvSize - 1) & 0xFF) ^ 0xAA);

        // Zero out the source pointers; copies must be unaffected.
        for (var i = 0; i < ySize; i++) {
          yPtr[i] = 0;
        }
        for (var i = 0; i < uvSize; i++) {
          uPtr[i] = 0;
          vPtr[i] = 0;
        }
        expect(yCopy[1], 1);
        expect(uCopy[0], 0x55);
        expect(vCopy[0], 0xAA);
      } finally {
        pkgffi.malloc.free(yPtr);
        pkgffi.malloc.free(uPtr);
        pkgffi.malloc.free(vPtr);
      }
    });
  });
}
