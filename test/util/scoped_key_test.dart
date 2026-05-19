// Unit tests for the shared scopedPrefsKey helper (X2).
//
// Locks in the wire format produced by both `Prefs._scopedKey` and
// `SharedPreferencesAdapter._prefixKey` so neither call site can drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/scoped_key.dart';

void main() {
  group('scopedPrefsKey', () {
    test('null prefix returns rawKey unchanged', () {
      expect(scopedPrefsKey('pinned_peers', null), 'pinned_peers');
    });

    test('empty prefix returns rawKey unchanged', () {
      expect(scopedPrefsKey('pinned_peers', ''), 'pinned_peers');
    });

    test(r'non-empty prefix produces `${rawKey}_${prefix}`', () {
      expect(
        scopedPrefsKey('pinned_peers', '0123456789ABCDEF'),
        'pinned_peers_0123456789ABCDEF',
      );
    });

    test('does not truncate the prefix — that is the caller\'s job', () {
      // Mirrors how Prefs._scopedKey pre-truncates the 76-char toxId before
      // calling scopedPrefsKey; the helper itself stays format-only.
      const longPrefix = '0123456789abcdef0123456789abcdef';
      expect(
        scopedPrefsKey('avatar_hash_friend1', longPrefix),
        'avatar_hash_friend1_$longPrefix',
      );
    });

    test(r'byte-identical to the legacy `${key}_${prefix}` string concat',
        () {
      // The legacy format both Prefs and SharedPreferencesAdapter used was
      // `'${key}_${prefix}'`. Lock it in.
      const k = 'group_owner_g1';
      const pfx = 'aaaaaaaaaaaaaaaa';
      // ignore: prefer_interpolation_to_compose_strings, prefer_adjacent_string_concatenation
      expect(scopedPrefsKey(k, pfx), k + '_' + pfx);
    });
  });
}
