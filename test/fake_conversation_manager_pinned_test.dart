// A7: FakeConversationManager.start() must await the initial pinned-read
// from Prefs so that getConversationList() never returns a freshly-loaded
// conversation as un-pinned just because the read hadn't resolved yet.
//
// This test seeds Prefs with a pinned C2C peer + a matching local friend,
// awaits start(), then calls getConversationList() and asserts the friend
// comes back with isPinned=true. Without the await this races on the
// fire-and-forget .then() that the previous implementation used.
//
// Skipped when the tim2tox FFI library isn't loadable (e.g. headless CI
// shards that don't bundle the dylib). FakeConversationManager requires an
// FfiChatService instance, which requires Tim2ToxFfi.open() at construction.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FakeConversationManager pinned init (A7)', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      // Set up a fake "current account" so scoped Prefs reads (getPinned /
      // getLocalFriends) resolve to a non-empty scope key.
      await Prefs.setCurrentAccountToxId(
          'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899');
    });

    tearDown(() async {
      await env.dispose();
    });

    test(
        'start() awaits initial pinned read; getConversationList() reports isPinned=true',
        () async {
      // Seed: one local friend, that friend pinned. We use a 64-char public
      // key so normalizeToxId is a no-op.
      const friendId =
          'FFEEDDCCBBAA99887766554433221100FFEEDDCCBBAA99887766554433221100';
      await Prefs.setLocalFriends({friendId});
      await Prefs.setFriendNickname(friendId, 'Alice');
      await Prefs.setPinned({friendId});

      final ffi = FfiChatService();
      final bus = FakeEventBus();
      final mgr = FakeConversationManager(bus, ffi);

      // Pre-A7, start() was synchronous and fire-and-forget; this `await`
      // is the contract we're locking in.
      await mgr.start();

      final list = await mgr.getConversationList();
      // The friend should appear in the list with isPinned=true. Other Tox
      // state (friends fetched via FFI) may add more entries, but we only
      // assert on the seeded friend.
      final seeded = list.where((c) => c.conversationID == 'c2c_$friendId');
      expect(seeded, isNotEmpty,
          reason: 'seeded local friend should appear in conversation list');
      expect(seeded.first.isPinned, isTrue,
          reason:
              'pinned flag must be set on first getConversationList() after awaited start()');

      mgr.dispose();
      bus.dispose();
    }, skip: skipReason);

    test('start() with empty pinned set leaves _pinned empty (no crash)',
        () async {
      // Seed local friend but no pinned set.
      const friendId =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      await Prefs.setLocalFriends({friendId});

      final ffi = FfiChatService();
      final bus = FakeEventBus();
      final mgr = FakeConversationManager(bus, ffi);

      await mgr.start();
      final list = await mgr.getConversationList();
      final seeded = list.where((c) => c.conversationID == 'c2c_$friendId');
      expect(seeded, isNotEmpty);
      expect(seeded.first.isPinned, isFalse);

      mgr.dispose();
      bus.dispose();
    }, skip: skipReason);
  });
}
