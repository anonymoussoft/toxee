// L1 — locks per-account toggle PERSISTENCE at the Prefs layer.
//
// Covers the persistence half of:
//   * S39 (auto-login restored per account on startup),
//   * S46 / S47 (auto-accept friends / group-invite toggles remembered per
//     account).
// The live delivery (auto-login actually logging in, auto-accept actually
// accepting an incoming request) is an L3 concern tested separately. Here we
// only verify that the toggle VALUES round-trip through SharedPreferences and
// that they are scoped per-account using the real on-disk key form
// `<const>_<first-16-of-toxId>` (NOT the `<const>:<toxId>` form that earlier
// docs incorrectly described).
//
// Pure Prefs: no FfiChatService, no FFI, no skip-guard. Prefs.initialize only
// needs a SharedPreferences instance, so no path_provider mock is required.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/scoped_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two 80-char toxIds whose first 16 chars DIFFER, so they must scope to
  // independent keys. (Length is arbitrary for scoping — the lock here is the
  // 16-char prefix, not the full-id length; a real Tox ID is 76 hex chars.)
  const toxIdA =
      'AAAAAAAAAAAAAAAA1111111111111111111111111111111111111111111111111111111111111111';
  const toxIdB =
      'BBBBBBBBBBBBBBBB2222222222222222222222222222222222222222222222222222222222222222';

  // Two toxIds that SHARE the same first 16 chars but differ afterwards (and
  // have different total lengths: 64 vs 80). Because scoping truncates to 16
  // chars, these two MUST collide onto the same scoped key — the differing
  // lengths make clear the alias comes from 16-char truncation, not equality.
  const sharedPrefix16 = 'CCCCCCCCCCCCCCCC';
  const toxIdShort = '${sharedPrefix16}333333333333333333333333333333333333333333333333'; // 64 chars total
  const toxIdLong = '${sharedPrefix16}4444444444444444444444444444444444444444444444444444444444444444'; // 80 chars total

  Future<void> resetPrefs() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    // Ensure no implicit "current account" leaks across tests so that passing
    // an explicit toxId is the only thing under test.
    await Prefs.setCurrentAccountToxId(null);
  }

  setUp(resetPrefs);

  group('scoped-key form (the lock: <const>_<first-16-of-toxId>)', () {
    test(
        'two toxIds with DIFFERENT first-16 prefixes have independent toggle values',
        () async {
      await Prefs.setAutoAcceptFriends(true, toxIdA);
      await Prefs.setAutoAcceptFriends(false, toxIdB);

      expect(await Prefs.getAutoAcceptFriends(toxIdA), isTrue,
          reason:
              'account A keeps its own value, unaffected by account B writing false');
      expect(await Prefs.getAutoAcceptFriends(toxIdB), isFalse,
          reason:
              'account B keeps its own value, unaffected by account A writing true');
    });

    test(
        'two toxIds SHARING the first-16 prefix collide onto the same scoped key',
        () async {
      // Sanity: the two ids really do share the first 16 chars and really do
      // differ in full length, so any collision can only come from 16-char
      // truncation (not from the ids being identical).
      expect(toxIdShort.substring(0, 16), equals(toxIdLong.substring(0, 16)),
          reason: 'precondition: first 16 chars are identical');
      expect(toxIdShort, isNot(equals(toxIdLong)),
          reason: 'precondition: the full toxIds differ');
      expect(toxIdShort.length, isNot(equals(toxIdLong.length)),
          reason: 'precondition: total lengths differ (64 vs 80)');

      await Prefs.setAutoAcceptFriends(true, toxIdShort);
      expect(await Prefs.getAutoAcceptFriends(toxIdLong), isTrue,
          reason:
              'scoping truncates to the first 16 chars, so the longer toxId '
              'reads the SAME stored value — proving 16-char (not full-id) scoping');

      // And flipping via the long id is observed through the short id too.
      await Prefs.setAutoAcceptFriends(false, toxIdLong);
      expect(await Prefs.getAutoAcceptFriends(toxIdShort), isFalse,
          reason: 'both ids alias the same underlying key in both directions');
    });

    test(
        'raw stored key matches the documented <const>_<first-16> form '
        '(acct_auto_accept_friends_<prefix>)', () async {
      await Prefs.setAutoAcceptFriends(true, toxIdA);

      final raw = await SharedPreferences.getInstance();
      final expectedKey =
          scopedPrefsKey('acct_auto_accept_friends', toxIdA.substring(0, 16));

      expect(expectedKey, equals('acct_auto_accept_friends_${toxIdA.substring(0, 16)}'),
          reason: 'the scoped key is the constant + "_" + first-16-of-toxId, '
              'NOT "<const>:<toxId>"');
      expect(raw.getBool(expectedKey), isTrue,
          reason:
              'setAutoAcceptFriends must persist under the scoped key (sans the '
              'plugin-internal "flutter." prefix that the mock strips on read)');
    });
  });

  group('auto-accept friends per-account round-trip (S46)', () {
    test('unset defaults to false', () async {
      expect(await Prefs.getAutoAcceptFriends(toxIdA), isFalse,
          reason: 'auto-accept friends defaults to false when never set');
    });

    test('set true then read true; flip to false then read false', () async {
      await Prefs.setAutoAcceptFriends(true, toxIdA);
      expect(await Prefs.getAutoAcceptFriends(toxIdA), isTrue,
          reason: 'value true must persist for the same account');

      await Prefs.setAutoAcceptFriends(false, toxIdA);
      expect(await Prefs.getAutoAcceptFriends(toxIdA), isFalse,
          reason: 'flipping to false must persist for the same account');
    });
  });

  group('auto-accept group invites per-account round-trip (S47)', () {
    test('unset defaults to false', () async {
      expect(await Prefs.getAutoAcceptGroupInvites(toxIdA), isFalse,
          reason: 'auto-accept group invites defaults to false when never set');
    });

    test('set true then read true; flip to false then read false', () async {
      await Prefs.setAutoAcceptGroupInvites(true, toxIdA);
      expect(await Prefs.getAutoAcceptGroupInvites(toxIdA), isTrue,
          reason: 'value true must persist for the same account');

      await Prefs.setAutoAcceptGroupInvites(false, toxIdA);
      expect(await Prefs.getAutoAcceptGroupInvites(toxIdA), isFalse,
          reason: 'flipping to false must persist for the same account');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setAutoAcceptGroupInvites(true, toxIdA);
      await Prefs.setAutoAcceptGroupInvites(false, toxIdB);
      expect(await Prefs.getAutoAcceptGroupInvites(toxIdA), isTrue,
          reason: 'account A group-invite toggle is independent of B');
      expect(await Prefs.getAutoAcceptGroupInvites(toxIdB), isFalse,
          reason: 'account B group-invite toggle is independent of A');
    });
  });

  group('auto-login per-account round-trip (S39)', () {
    test('unset defaults to true (per-account default)', () async {
      expect(await Prefs.getAutoLogin(toxIdA), isTrue,
          reason: 'auto-login defaults to true for a new/unset account');
    });

    test('set false then read false; flip back to true then read true',
        () async {
      await Prefs.setAutoLogin(false, toxIdA);
      expect(await Prefs.getAutoLogin(toxIdA), isFalse,
          reason: 'disabling auto-login must persist for the same account');

      await Prefs.setAutoLogin(true, toxIdA);
      expect(await Prefs.getAutoLogin(toxIdA), isTrue,
          reason: 're-enabling auto-login must persist for the same account');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setAutoLogin(false, toxIdA);
      // B never set -> falls through to its per-account default (true).
      expect(await Prefs.getAutoLogin(toxIdA), isFalse,
          reason: 'account A auto-login=false does not affect account B');
      expect(await Prefs.getAutoLogin(toxIdB), isTrue,
          reason: 'account B retains its per-account default of true');
    });
  });

  group('notification sound per-account round-trip', () {
    test('unset defaults to true', () async {
      expect(await Prefs.getNotificationSoundEnabled(toxIdA), isTrue,
          reason: 'notification sound defaults to true for an unset account');
    });

    test('set false then read false; flip back to true then read true',
        () async {
      await Prefs.setNotificationSoundEnabled(false, toxIdA);
      expect(await Prefs.getNotificationSoundEnabled(toxIdA), isFalse,
          reason: 'disabling notification sound must persist for the account');

      await Prefs.setNotificationSoundEnabled(true, toxIdA);
      expect(await Prefs.getNotificationSoundEnabled(toxIdA), isTrue,
          reason: 're-enabling notification sound must persist for the account');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setNotificationSoundEnabled(false, toxIdA);
      await Prefs.setNotificationSoundEnabled(true, toxIdB);
      expect(await Prefs.getNotificationSoundEnabled(toxIdA), isFalse,
          reason: 'account A notification-sound toggle is independent of B');
      expect(await Prefs.getNotificationSoundEnabled(toxIdB), isTrue,
          reason: 'account B notification-sound toggle is independent of A');
    });
  });
}
