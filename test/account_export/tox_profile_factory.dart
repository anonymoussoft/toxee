// Minimal helper that builds a real tox_profile.tox-shaped blob inside a
// test process by calling the toxcore symbols re-exported from
// libtim2tox_ffi.dylib via dart:ffi.
//
// We deliberately avoid going through Tim2ToxFfi or any of the higher-level
// toxee/Tim2Tox wiring — the goal is to produce a savedata blob that the
// production extractToxIdFromProfileNative() will accept, with no side
// effects on global Tim2Tox state.
//
// Returns null if the FFI dylib could not be located/opened in this
// environment (some CI configurations don't ship it).

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

/// Public-key-derived 76-hex-char Tox ID (uppercase, no nospam/checksum).
class ToxProfileFixture {
  ToxProfileFixture({
    required this.savedata,
    required this.toxId,
    required this.publicKeyHex,
  });

  final Uint8List savedata;
  final String toxId; // 76 uppercase hex chars (public key + nospam + checksum)
  final String publicKeyHex; // 64 uppercase hex chars

  static ToxProfileFixture? create() {
    final ffi.DynamicLibrary lib;
    try {
      // Reuse Tim2ToxFfi.open()'s lookup, since we already proved it loads
      // under flutter test. We only need a handle for symbol lookup.
      Tim2ToxFfi.open();
      // The cleanest way to get the underlying handle is to re-open the
      // same library: dlopen will return the cached handle on macOS/Linux.
      if (Platform.isMacOS) {
        lib = ffi.DynamicLibrary.open('libtim2tox_ffi.dylib');
      } else if (Platform.isLinux) {
        lib = ffi.DynamicLibrary.open('libtim2tox_ffi.so');
      } else if (Platform.isWindows) {
        lib = ffi.DynamicLibrary.open('tim2tox_ffi.dll');
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }

    // Lookup minimal toxcore symbols.
    final toxOptionsNew = lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>)>('tox_options_new');
    final toxOptionsDefault = lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('tox_options_default');
    final toxOptionsFree = lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('tox_options_free');
    final toxNew = lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint32>)>('tox_new');
    final toxKill = lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('tox_kill');
    final toxGetSavedataSize = lib.lookupFunction<
        ffi.IntPtr Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('tox_get_savedata_size');
    final toxGetSavedata = lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
        void Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint8>)>('tox_get_savedata');
    final toxSelfGetPublicKey = lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
        void Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint8>)>('tox_self_get_public_key');
    final toxSelfGetAddress = lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
        void Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint8>)>('tox_self_get_address');

    final options = toxOptionsNew(ffi.Pointer.fromAddress(0));
    if (options == ffi.nullptr) return null;
    toxOptionsDefault(options);

    final errPtr = pkgffi.malloc<ffi.Uint32>();
    try {
      errPtr.value = 0;
      final tox = toxNew(options, errPtr);
      toxOptionsFree(options);
      if (tox == ffi.nullptr || errPtr.value != 0) {
        return null;
      }
      try {
        final size = toxGetSavedataSize(tox);
        if (size <= 0) return null;
        final saveBuf = pkgffi.malloc<ffi.Uint8>(size);
        final pkBuf = pkgffi.malloc<ffi.Uint8>(32);
        final addrBuf = pkgffi.malloc<ffi.Uint8>(38);
        try {
          toxGetSavedata(tox, saveBuf);
          toxSelfGetPublicKey(tox, pkBuf);
          toxSelfGetAddress(tox, addrBuf);
          final saveBytes = Uint8List.fromList(
              saveBuf.asTypedList(size));
          final pkHex = _toHexUpper(pkBuf.asTypedList(32));
          final addrHex = _toHexUpper(addrBuf.asTypedList(38));
          return ToxProfileFixture(
              savedata: saveBytes, toxId: addrHex, publicKeyHex: pkHex);
        } finally {
          pkgffi.malloc.free(saveBuf);
          pkgffi.malloc.free(pkBuf);
          pkgffi.malloc.free(addrBuf);
        }
      } finally {
        toxKill(tox);
      }
    } finally {
      pkgffi.malloc.free(errPtr);
    }
  }
}

String _toHexUpper(List<int> bytes) {
  const hex = '0123456789ABCDEF';
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(hex[(b >> 4) & 0xF]);
    sb.write(hex[b & 0xF]);
  }
  return sb.toString();
}
