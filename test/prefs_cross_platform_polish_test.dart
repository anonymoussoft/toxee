// Tests for the PR6 cross-platform polish changes to Prefs:
//
//   - C9: getAccountByToxId uses firstWhereOrNull, preserves the documented
//     fallback ordering (exact → case-insensitive → 64-char prefix →
//     compareToxIds), and returns null when nothing matches without
//     throwing.
//   - C10: importScopedPrefsForAccount skips malformed entries and
//     continues with the rest, instead of failing the whole import.
//
// These are pure-Dart tests; no FFI / path_provider / native channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  group('getAccountByToxId fallback ordering (C9)', () {
    // A 64-hex-character toxId; the only constraint we exercise here is
    // length >= 64 (so the prefix-match branch can fire).
    const String longId =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    test('returns null when account list is empty', () async {
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNull);
    });

    test('exact match (case-sensitive) wins over case-insensitive', () async {
      // Seed two accounts: one matches case-insensitively, one matches
      // exactly. The exact match must be returned.
      final lowered = longId.toLowerCase();
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': lowered, 'nickname': 'lower'},
        <String, String>{'toxId': longId, 'nickname': 'exact'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNotNull);
      expect(found!['nickname'], 'exact');
    });

    test('falls back to case-insensitive when no exact match', () async {
      final lowered = longId.toLowerCase();
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': lowered, 'nickname': 'lower-only'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNotNull);
      expect(found!['nickname'], 'lower-only');
    });

    test('returns null cleanly (no StateError) when nothing matches',
        () async {
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': 'ZZZZ', 'nickname': 'unrelated'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNull);
    });
  });

  group('importScopedPrefsForAccount partial-restore (C10)', () {
    const String toxId =
        'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
    const String prefix16 = 'BBBBBBBBBBBBBBBB';

    test('skips a malformed List entry and continues with the rest',
        () async {
      // Construct a payload where one entry is a List<dynamic> whose
      // elements are NOT all strings. The old implementation would crash
      // the entire import via .cast<String>() → SharedPreferences setter.
      // The new implementation logs + skips that one and proceeds.
      final payload = <String, dynamic>{
        'good_string': 'hello',
        'bad_list': <Object>[1, 2, 3], // ints, not strings
        'good_int': 42,
      };

      await Prefs.importScopedPrefsForAccount(toxId, payload);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('good_string_$prefix16'), 'hello');
      expect(prefs.getInt('good_int_$prefix16'), 42);
      // The bad list key was skipped — no entry should exist.
      expect(prefs.getStringList('bad_list_$prefix16'), isNull);
    });

    test('empty toxId is a no-op', () async {
      await Prefs.importScopedPrefsForAccount('', <String, dynamic>{
        'foo': 'bar',
      });
      final prefs = await SharedPreferences.getInstance();
      // No scoped key should have been written.
      expect(prefs.getKeys().where((k) => k.startsWith('foo_')), isEmpty);
    });
  });

  // Codex Round 6 / A1-P1 regression: after the F12 short-toxId backfill
  // rewrites an account row from a 64-char public key to the 76-char full
  // Tox ID, subsequent addAccount() calls from `AccountSwitcher` or
  // `LoginUseCase` keep passing the pre-backfill 64-char form alongside a
  // (possibly unchanged) nickname. The old raw `acc['toxId'] != toxId`
  // dup-detection would then see "another account with the same nickname"
  // because the stored toxId is 76 chars and the incoming one is 64. The
  // fix swaps in `compareToxIds`, which normalizes both forms to the
  // 64-char public-key prefix before comparing.
  group('addAccount nickname-dup uses compareToxIds (A1-P1)', () {
    const String pubKey64 =
        'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
    // 76-char full Tox ID: public key + 8-char nospam + 4-char checksum.
    // The first 64 chars must match `pubKey64` so `compareToxIds` treats
    // them as the same identity.
    const String fullId76 = '${pubKey64}1234567800AB';

    test(
        'same-account update with shorter toxId + same nickname does not throw',
        () async {
      // Simulate the post-backfill state: account_list row carries the
      // 76-char form, but the caller still has only the 64-char public key
      // (e.g. AccountSwitcher reads its argument from the sidebar tile,
      // which was captured before the running session triggered backfill).
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{
          'toxId': fullId76,
          'nickname': 'Alice',
        },
      ]);

      // Same nickname, shorter toxId → must update in place, not throw.
      await Prefs.addAccount(toxId: pubKey64, nickname: 'Alice');

      final accounts = await Prefs.getAccountList();
      expect(accounts.length, 1,
          reason:
              'addAccount should update the existing row, not duplicate it');
      expect(accounts.first['nickname'], 'Alice');
    });

    test(
        'genuine nickname collision against a different account still throws',
        () async {
      // Two unrelated accounts. Adding a third with a fresh toxId but a
      // nickname that collides with one of them must still be rejected —
      // we only want the fuzzy match to suppress *self*-collisions.
      const String otherId64 =
          'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': fullId76, 'nickname': 'Alice'},
        <String, String>{'toxId': otherId64, 'nickname': 'Bob'},
      ]);
      const String newId64 =
          'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
      expect(
        () => Prefs.addAccount(toxId: newId64, nickname: 'Alice'),
        throwsStateError,
      );
    });

    test('same-account 64-char + 64-char path is unaffected', () async {
      // Sanity check the unchanged-shape path: stored 64-char, incoming
      // 64-char, identical strings → updateLastLogin path, no throw.
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': pubKey64, 'nickname': 'Alice'},
      ]);
      await Prefs.addAccount(toxId: pubKey64, nickname: 'Alice');
      final accounts = await Prefs.getAccountList();
      expect(accounts.length, 1);
    });
  });
}
