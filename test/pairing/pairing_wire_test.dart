import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/pairing/pairing_wire.dart';

/// S91 (cross-device pairing) — wire-framing half. The pairing TCP socket frames
/// every message as a big-endian uint32 length prefix + payload
/// ([PairingFrame.encode] / [PairingFrameReader]). This is pure logic and is the
/// one pairing primitive that previously had no dedicated test (crypto, SAS, the
/// QR URL round-trip, and the e2e host/client handshake are already gated by the
/// sibling test/pairing/*.dart). No camera, no two devices, no socket — the
/// length-prefix protocol either round-trips byte-for-byte or it does not.
void main() {
  Uint8List bytes(List<int> xs) => Uint8List.fromList(xs);

  Future<List<Uint8List>> collect(
    void Function(PairingFrameReader r) drive,
  ) async {
    final reader = PairingFrameReader();
    final got = <Uint8List>[];
    final done = Completer<void>();
    reader.frames.listen(
      got.add,
      onError: done.completeError,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    drive(reader);
    await reader.close();
    await done.future;
    return got;
  }

  test('S91 wire: encode → reader round-trips a single payload byte-for-byte',
      () async {
    final payload = bytes(List<int>.generate(256, (i) => i & 0xFF));
    final frame = PairingFrame.encode(payload);
    // 4-byte length prefix + payload.
    expect(frame.length, 4 + payload.length);

    final got = await collect((r) => r.feed(frame));
    expect(got, hasLength(1));
    expect(got.single, payload);
  });

  test('S91 wire: reassembles a frame fed one byte at a time', () async {
    final payload = bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    final frame = PairingFrame.encode(payload);

    final got = await collect((r) {
      for (final b in frame) {
        r.feed([b]);
      }
    });
    expect(got, hasLength(1));
    expect(got.single, payload);
  });

  test('S91 wire: splits two frames delivered in a single chunk', () async {
    final a = bytes([10, 20, 30]);
    final b = bytes([40, 50]);
    final combined = BytesBuilder()
      ..add(PairingFrame.encode(a))
      ..add(PairingFrame.encode(b));

    final got = await collect((r) => r.feed(combined.toBytes()));
    expect(got, hasLength(2));
    expect(got[0], a);
    expect(got[1], b);
  });

  test('S91 wire: an empty payload round-trips (length 0 frame)', () async {
    final frame = PairingFrame.encode(bytes([]));
    expect(frame.length, 4);
    final got = await collect((r) => r.feed(frame));
    expect(got, hasLength(1));
    expect(got.single, isEmpty);
  });

  test('S91 wire: encode rejects a payload over the max', () {
    final tooBig = Uint8List(PairingFrame.maxPayloadBytes + 1);
    expect(() => PairingFrame.encode(tooBig), throwsArgumentError);
  });

  test('S91 wire: reader rejects an oversized length prefix (loud, no OOM)',
      () async {
    // Hand-craft a header claiming a payload bigger than maxPayloadBytes.
    final header = Uint8List(4);
    ByteData.view(header.buffer)
        .setUint32(0, PairingFrame.maxPayloadBytes + 1, Endian.big);
    final reader = PairingFrameReader();
    final err = Completer<Object>();
    reader.frames.listen(
      (_) {},
      onError: err.complete,
      onDone: () {
        if (!err.isCompleted) err.completeError('closed without error');
      },
    );
    reader.feed(header);
    expect(await err.future, isA<FormatException>());
  });

  test('S91 wire: closing mid-frame raises a clean error, not a hang', () async {
    final payload = bytes([1, 2, 3, 4]);
    final frame = PairingFrame.encode(payload);
    // Feed everything except the last byte, then close.
    final reader = PairingFrameReader();
    final err = Completer<Object>();
    reader.frames.listen(
      (_) {},
      onError: err.complete,
      onDone: () {
        if (!err.isCompleted) err.completeError('closed cleanly, expected error');
      },
    );
    reader.feed(frame.sublist(0, frame.length - 1));
    await reader.close();
    expect(await err.future, isA<FormatException>());
  });
}
