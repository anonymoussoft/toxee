// Regression test for tim2tox `Tim2ToxSdkPlatform.setFriendInfo`.
//
// S9 from the 2026-05-18 local-storage review: `setFriendInfo` returned
// `code: 0 "success"` without persisting anything. The UIKit profile-page
// "set friend remark" silently failed.
//
// The fix routes `friendRemark` through the typed
// `ExtendedPreferencesService.setFriendRemark` so the host adapter applies
// its per-account scoping (toxee scopes by current Tox-ID prefix); the same
// scope is read back in `fakeUserToV2TimFriendInfo` so the alias becomes
// visible across the contact list, search, and chat headers — not just the
// editing UI's ephemeral state.
//
// `friendCustomInfo` has no place to land in the current
// `ExtendedPreferencesService` interface and is intentionally a TODO; this
// test confirms the remark side now persists.
//
// FFI dependency: `Tim2ToxSdkPlatform`'s constructor requires a real
// `FfiChatService`, which opens the tim2tox FFI library. Skipped when the
// library is not loadable in this environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

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

  group('Tim2ToxSdkPlatform.setFriendInfo', skip: skipReason, () {
    late _InMemoryPrefs prefs;
    late FfiChatService ffi;
    late Tim2ToxSdkPlatform platform;

    setUp(() {
      prefs = _InMemoryPrefs();
      ffi = FfiChatService(preferencesService: prefs);
      platform = Tim2ToxSdkPlatform(
        ffiService: ffi,
        preferencesService: prefs,
      );
    });

    test('persists friendRemark via the typed setFriendRemark API', () async {
      const userID = 'peer-alice';
      const remark = 'Alice (from work)';

      final cb = await platform.setFriendInfo(
        userID: userID,
        friendRemark: remark,
      );
      expect(cb.code, 0);

      // Read back via the same typed API the converter uses, so this test
      // does not depend on the host adapter's internal key shape. What
      // matters is that the round-trip (setFriendInfo → getFriendRemark)
      // returns the value — that's what makes the alias visible to the
      // contact list and chat headers via the converter.
      final stored = await prefs.getFriendRemark(userID);
      expect(stored, remark);
    });

    test('returns success when friendRemark is null (no-op write)', () async {
      const userID = 'peer-bob';
      final cb = await platform.setFriendInfo(userID: userID);
      expect(cb.code, 0);
      expect(await prefs.getFriendRemark(userID), isNull);
    });

    test('friendCustomInfo is accepted but not yet persisted (TODO)', () async {
      // Documenting current behavior: the interface has no per-friend custom
      // map yet, so we accept the call to keep UIKit happy and drop the map
      // silently. If/when we widen `ExtendedPreferencesService`, this test
      // should be flipped to assert the value is stored.
      const userID = 'peer-carol';
      final cb = await platform.setFriendInfo(
        userID: userID,
        friendCustomInfo: const {'department': 'eng'},
      );
      expect(cb.code, 0);
    });
  });
}

class _InMemoryPrefs implements ExtendedPreferencesService {
  final Map<String, Object?> _store = {};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => _store[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async {
    _store[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => _store[key] as int?;

  @override
  Future<void> setInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      _store[key] == null ? null : List<String>.from(_store[key] as List);

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _store[key] = List<String>.from(value);
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  // Friend remark: matches the host adapter's behavior except for scoping.
  // The production toxee adapter writes under `friend_remark_<id>_<scope>`;
  // the test only cares about round-trip, so we use the bare key.
  @override
  Future<String?> getFriendRemark(String friendId) async =>
      _store['friend_remark_$friendId'] as String?;

  @override
  Future<void> setFriendRemark(String friendId, String? remark) async {
    if (remark == null || remark.isEmpty) {
      _store.remove('friend_remark_$friendId');
    } else {
      _store['friend_remark_$friendId'] = remark;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        'InMemoryPrefs does not implement ${invocation.memberName}');
  }
}
