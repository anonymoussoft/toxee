// A9: FakeConversationManager.deleteConversation was a stub no-op. After
// the fix it must clear the underlying chat history (so the next poll
// doesn't re-emit the same messages), remove the pinned flag, and emit a
// refresh.
//
// We assert two things:
//   1. clearC2CHistory / clearGroupHistory is invoked with the normalized id.
//   2. The conversation is dropped from the manager's pinned set.
//
// We use a thin _RecordingFfiChatService that subclasses the real
// FfiChatService and overrides the two clear* methods to record their
// arguments. The real constructor needs Tim2ToxFfi.open() so the test is
// skipped when the FFI library isn't loadable.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

class _RecordingFfiChatService extends FfiChatService {
  _RecordingFfiChatService() : super();

  final List<String> clearedC2C = [];
  final List<String> clearedGroup = [];

  @override
  Future<void> clearC2CHistory(String userID) async {
    clearedC2C.add(userID);
    // Skip the real FFI path — we only need the recording side-effect.
  }

  @override
  Future<void> clearGroupHistory(String groupID) async {
    clearedGroup.add(groupID);
  }
}

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

  group('FakeConversationManager.deleteConversation (A9)', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      await Prefs.setCurrentAccountToxId(
          '0000000000000000111122223333444455556666777788889999AABBCCDDEEFF');
    });

    tearDown(() async {
      await env.dispose();
    });

    test('C2C: clears history, drops from pinned, normalizes ID', () async {
      const friendId =
          'FFEEDDCCBBAA99887766554433221100FFEEDDCCBBAA99887766554433221100';
      // Pre-seed friend in local persistence + pinned so we can observe the
      // pinned-set update.
      await Prefs.setLocalFriends({friendId});
      await Prefs.setFriendNickname(friendId, 'Alice');
      await Prefs.setPinned({friendId});

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final mgr = FakeConversationManager(bus, ffi);
      await mgr.start();

      // Sanity check: the seeded conversation is pinned before deletion.
      final listBefore = await mgr.getConversationList();
      final beforeMatch =
          listBefore.where((c) => c.conversationID == 'c2c_$friendId');
      expect(beforeMatch, isNotEmpty);
      expect(beforeMatch.first.isPinned, isTrue);

      // Pass the raw conversationID with the c2c_ prefix.
      await mgr.deleteConversation('c2c_$friendId');

      expect(ffi.clearedC2C, contains(friendId),
          reason:
              'clearC2CHistory must be called with the normalized user id');
      expect(ffi.clearedGroup, isEmpty);

      // Pinned flag must be gone.
      final pinnedAfter = await Prefs.getPinned();
      expect(pinnedAfter.contains(friendId), isFalse,
          reason: 'deleted conversation must not remain in pinned set');

      // Conversation list now shows the friend un-pinned (friend itself
      // still exists in local persistence, but isPinned should be false).
      final listAfter = await mgr.getConversationList();
      final afterMatch =
          listAfter.where((c) => c.conversationID == 'c2c_$friendId');
      if (afterMatch.isNotEmpty) {
        expect(afterMatch.first.isPinned, isFalse);
      }

      mgr.dispose();
      bus.dispose();
    }, skip: skipReason);

    test('group: clears group history and drops pinned key', () async {
      const gid = 'tox_42';
      // Seed a pinned group.
      await Prefs.setPinned({'group_$gid'});

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final mgr = FakeConversationManager(bus, ffi);
      await mgr.start();

      await mgr.deleteConversation('group_$gid');

      expect(ffi.clearedGroup, contains(gid));
      expect(ffi.clearedC2C, isEmpty);

      final pinnedAfter = await Prefs.getPinned();
      expect(pinnedAfter.contains('group_$gid'), isFalse);

      mgr.dispose();
      bus.dispose();
    }, skip: skipReason);

    test('invalid conversationID is a no-op', () async {
      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final mgr = FakeConversationManager(bus, ffi);
      await mgr.start();

      for (final bad in const ['', 'c2c_', 'group_']) {
        await mgr.deleteConversation(bad);
      }
      expect(ffi.clearedC2C, isEmpty);
      expect(ffi.clearedGroup, isEmpty);

      mgr.dispose();
      bus.dispose();
    }, skip: skipReason);
  });
}
