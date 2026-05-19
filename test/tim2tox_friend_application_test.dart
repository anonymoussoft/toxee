// Regression test for tim2tox friend-application dismissal.
//
// S8 from the 2026-05-18 local-storage review: `refuseFriendApplication` and
// `deleteFriendApplication` on `Tim2ToxSdkPlatform` were no-ops that returned
// `code: 0 "success"` without doing anything. The C++ application queue was
// never told to drop them, so rejected friend requests came back on every 5s
// poll and ghost entries persisted across restarts.
//
// The fix records dismissed application user IDs in a persistent set (via the
// injected `ExtendedPreferencesService`) and filters them out of
// `getFriendApplications`. This test exercises both layers:
//   1. the static `FfiChatService.filterDismissedApplications` (pure, no FFI),
//      which guarantees a dismissed userID is removed from a candidate list;
//   2. `FfiChatService.refuseFriendApplication` / `deleteFriendApplication`
//      end-to-end through a stub `ExtendedPreferencesService`, asserting the
//      dismissed userID is persisted under the documented preferences key.
//
// FFI dependency: only the end-to-end portion needs `Tim2ToxFfi.open()` —
// skipped when the library is not loadable. The filter test is pure Dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
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
  group('FfiChatService.filterDismissedApplications', () {
    test('returns the input unchanged when the dismissed set is empty', () {
      final apps = [
        (userId: 'alice', wording: 'hi'),
        (userId: 'bob', wording: 'add me'),
      ];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        const <String>{},
      );
      expect(result, apps);
    });

    test('drops applications whose userID is in the dismissed set', () {
      final apps = [
        (userId: 'alice', wording: 'hi'),
        (userId: 'bob', wording: 'add me'),
        (userId: 'carol', wording: 'hello'),
      ];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        {'bob'},
      );
      expect(result.map((app) => app.userId), ['alice', 'carol']);
    });

    test('normalizes 76-char Tox addresses down to the 64-char public key',
        () {
      // Native applications surface a 64-char public key; UI/dismissal calls
      // can carry the full 76-char address. Filter normalizes the input
      // userID to its 64-char prefix before comparing against `dismissed`,
      // so a 64-char key in the dismissed set still matches.
      final fullAddress = 'a' * 76;
      final publicKey = 'a' * 64;
      final apps = [(userId: fullAddress, wording: 'long form')];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        {publicKey},
      );
      expect(result, isEmpty);
    });
  });

  group('FfiChatService friend-application dismissal persistence',
      skip: _ffiAvailable()
          ? null
          : 'tim2tox FFI library not loadable in this environment', () {
    late _InMemoryPrefs prefs;
    late FfiChatService service;

    setUp(() {
      prefs = _InMemoryPrefs();
      service = FfiChatService(preferencesService: prefs);
    });

    test(
        'refuseFriendApplication persists the user ID under the documented key',
        () async {
      const userID = 'peer-to-refuse';
      await service.refuseFriendApplication(userID);

      final stored =
          await prefs.getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored, isNotNull);
      expect(stored!.toSet(), {userID});

      // Subsequent getFriendApplications() — production-path read — must not
      // surface this dismissed user. The native queue is empty here, so we
      // verify the filter does not regress (no FFI applications + dismissed
      // entry → empty list).
      final apps = await service.getFriendApplications();
      expect(apps.any((a) => a.userId == userID), isFalse);
    });

    test('deleteFriendApplication has the same dismissal effect', () async {
      const userID = 'peer-to-delete';
      await service.deleteFriendApplication(userID);

      final stored =
          await prefs.getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored, isNotNull);
      expect(stored!.toSet(), {userID});
    });

    test('refuseFriendApplication is idempotent (no duplicate IDs persisted)',
        () async {
      const userID = 'peer-idempotent';
      await service.refuseFriendApplication(userID);
      await service.refuseFriendApplication(userID);

      final stored =
          await prefs.getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored!.length, 1);
    });

    test('acceptFriendRequest clears any prior dismissal for the same user',
        () async {
      const userID = 'peer-reapply';
      await service.refuseFriendApplication(userID);
      var stored = await prefs
          .getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored!.toSet(), {userID});

      // acceptFriendRequest hits the FFI to actually accept the friend; the
      // FFI side-effect on an unknown user is harmless in this isolated
      // process (no Tox instance running), but the local cleanup of the
      // dismissed set is the behavior we are asserting.
      await service.acceptFriendRequest(userID);
      stored = await prefs
          .getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored ?? <String>[], isEmpty);
    });
  });
}

/// Minimal in-memory ExtendedPreferencesService used by the dismissal tests.
///
/// Implements only the methods our friend-application code path touches and
/// throws UnimplementedError for the rest, so any accidental usage of an
/// unmocked surface is loud rather than silently wrong.
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
  Future<List<String>?> getStringList(String key) async {
    final v = _store[key];
    return v == null ? null : List<String>.from(v as List);
  }

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

  // Unused by these tests — fail loudly if touched.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        'InMemoryPrefs does not implement ${invocation.memberName}');
  }
}
