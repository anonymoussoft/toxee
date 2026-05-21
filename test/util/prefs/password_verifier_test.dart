// Unit tests for [PasswordVerifier] — the PBKDF2/SHA-256 password hashing
// + verification extracted from `lib/util/prefs.dart`.
//
// All tests use injected dependencies (a [FakeSecureStorageFacade] backed
// by an in-memory `Map<String, String>`, plus an in-memory
// [LegacyPasswordStore]) so no platform channels are involved. A
// [ThrowingSecureStorageFacade] simulates the swallowed-write failure mode
// (e.g. sandboxed macOS without keychain entitlement) that the real
// [FlutterSecureStorageFacade] reduces to `write -> false`.

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

/// In-memory [SecureStorageFacade] for tests. Backed by a `Map<String,
/// String>` so successful reads/writes/deletes behave like a working
/// platform keychain.
class FakeSecureStorageFacade implements SecureStorageFacade {
  final Map<String, String> entries = <String, String>{};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<bool> write(String key, String value) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    entries.remove(key);
    return true;
  }
}

/// [SecureStorageFacade] whose `write` always returns `false` — simulates
/// the swallowed `MissingPluginException` / `PlatformException` that the
/// real [FlutterSecureStorageFacade] turns into `false`. Reads return null
/// (no usable persisted value) and deletes report success so the
/// `removePassword` legacy-cleanup path is not gated. Used to pin the
/// invariant "legacy verify still returns true even when the PBKDF2
/// migration write fails — keychain failure must not lock the user out".
class ThrowingSecureStorageFacade implements SecureStorageFacade {
  int writeAttempts = 0;

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async {
    writeAttempts++;
    return false;
  }

  @override
  Future<bool> delete(String key) async => true;
}

/// In-memory [LegacyPasswordStore] for tests. Backed by a `Map<String,
/// String>` so the migration paths can be exercised deterministically.
class FakeLegacyPasswordStore implements LegacyPasswordStore {
  final Map<String, String> hashes = <String, String>{};
  final Map<String, String> salts = <String, String>{};

  @override
  Future<String?> readLegacyHash(String toxId) async => hashes[toxId];

  @override
  Future<String?> readLegacySalt(String toxId) async => salts[toxId];

  @override
  Future<void> removeLegacyHash(String toxId) async {
    hashes.remove(toxId);
  }

  @override
  Future<void> removeLegacySalt(String toxId) async {
    salts.remove(toxId);
  }
}

PasswordVerifier _buildVerifier({
  FakeLegacyPasswordStore? legacy,
  SecureStorageFacade? secureStorage,
}) {
  return PasswordVerifier(
    secureStorage: secureStorage ?? FakeSecureStorageFacade(),
    legacyStore: legacy ?? FakeLegacyPasswordStore(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toxId = '0123456789ABCDEF';

  group('PasswordVerifier — PBKDF2 round trip', () {
    test('verifyPassword accepts the same password that was set', () async {
      final v = _buildVerifier();
      expect(await v.setPassword(toxId, 'correct horse battery staple'), isTrue);
      expect(
        await v.verifyPassword(toxId, 'correct horse battery staple'),
        isTrue,
      );
    });

    test('verifyPassword rejects a wrong password', () async {
      final v = _buildVerifier();
      await v.setPassword(toxId, 'right');
      expect(await v.verifyPassword(toxId, 'wrong'), isFalse);
    });

    test('verifyPassword returns false when no password has ever been set',
        () async {
      final v = _buildVerifier();
      expect(await v.verifyPassword(toxId, 'anything'), isFalse);
    });

    test('hasPassword reflects setPassword / removePassword', () async {
      final v = _buildVerifier();
      expect(await v.hasPassword(toxId), isFalse);
      await v.setPassword(toxId, 'hunter2');
      expect(await v.hasPassword(toxId), isTrue);
      expect(await v.removePassword(toxId), isTrue);
      expect(await v.hasPassword(toxId), isFalse);
    });

    test('setPassword with empty string clears any existing password',
        () async {
      final v = _buildVerifier();
      await v.setPassword(toxId, 'will-be-cleared');
      expect(await v.hasPassword(toxId), isTrue);
      expect(await v.setPassword(toxId, ''), isTrue);
      expect(await v.hasPassword(toxId), isFalse);
    });

    test('setPassword throws ArgumentError on empty toxId', () async {
      final v = _buildVerifier();
      expect(
        () => v.setPassword('', 'whatever'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('verifyPassword returns false on empty toxId or empty password',
        () async {
      final v = _buildVerifier();
      await v.setPassword(toxId, 'p');
      expect(await v.verifyPassword('', 'p'), isFalse);
      expect(await v.verifyPassword(toxId, ''), isFalse);
    });
  });

  group('PasswordVerifier — wire format', () {
    test('stored hash carries the "pbkdf2:" prefix (versioning marker)',
        () async {
      final v = _buildVerifier();
      await v.setPassword(toxId, 'sentinel');
      final stored = await v.getPasswordHash(toxId);
      expect(stored, isNotNull);
      expect(stored!.startsWith(PasswordVerifier.pbkdf2Prefix), isTrue,
          reason: 'PasswordVerifier must persist the pbkdf2: prefix so the '
              'verify path can distinguish modern PBKDF2 hashes from legacy '
              'SHA-256 entries.');
    });

    test('salt is fresh per call — same password produces different stored '
        'hashes across two setPassword invocations', () async {
      final v = _buildVerifier();
      await v.setPassword(toxId, 'same-password');
      final first = await v.getPasswordHash(toxId);
      await v.setPassword(toxId, 'same-password');
      final second = await v.getPasswordHash(toxId);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(equals(second)),
          reason: 'Each setPassword must generate a new random salt — '
              'otherwise two accounts with the same password would have '
              'identical stored hashes.');
    });

    test('PBKDF2 parameters are locked to (150_000, 256, SHA-256)', () {
      // Pinning constants — changing these silently breaks every stored
      // password. Bump only with a documented migration.
      expect(PasswordVerifier.pbkdf2Iterations, 150000);
      expect(PasswordVerifier.pbkdf2Bits, 256);
      expect(PasswordVerifier.pbkdf2Prefix, 'pbkdf2:');
    });

    test('legacy key formats are stable', () {
      // The legacy plain-prefs keys are read-only on migration; their
      // format must not drift or pre-S1 installs lose their password.
      expect(PasswordVerifier.legacyHashKey('abc'), 'account_password_abc');
      expect(PasswordVerifier.legacySaltKey('abc'), 'account_password_salt_abc');
      expect(PasswordVerifier.legacySaltPrefix, 'account_password_salt_');
    });
  });

  group('PasswordVerifier — legacy SHA-256 migration', () {
    test('legacy unsalted SHA-256 hash verifies and is upgraded to PBKDF2',
        () async {
      final legacy = FakeLegacyPasswordStore();
      const password = 'legacy-pw';
      // Pre-seed the legacy store with an unsalted SHA-256 of the password
      // (the pre-S1 storage format).
      legacy.hashes[toxId] = crypto.sha256.convert(utf8.encode(password)).toString();
      // No salt in legacy store — this is the unsalted branch.
      final v = _buildVerifier(legacy: legacy);

      expect(await v.verifyPassword(toxId, password), isTrue);
      // After successful verify, the password must be re-hashed with PBKDF2
      // and stored in secure storage. The legacy entry is dropped.
      final upgraded = await v.getPasswordHash(toxId);
      expect(upgraded, isNotNull);
      expect(upgraded!.startsWith(PasswordVerifier.pbkdf2Prefix), isTrue);
      expect(legacy.hashes.containsKey(toxId), isFalse,
          reason: 'Legacy hash entry must be dropped after successful '
              'PBKDF2 migration so it is not used again.');
    });

    test('legacy salted SHA-256 hash verifies and is upgraded to PBKDF2',
        () async {
      final legacy = FakeLegacyPasswordStore();
      const password = 'legacy-salted-pw';
      const saltB64 = 'c2FsdHk='; // base64 of "salty"
      legacy.hashes[toxId] = crypto.sha256
          .convert(utf8.encode('$saltB64$password'))
          .toString();
      legacy.salts[toxId] = saltB64;
      final v = _buildVerifier(legacy: legacy);

      expect(await v.verifyPassword(toxId, password), isTrue);
      final upgraded = await v.getPasswordHash(toxId);
      expect(upgraded, isNotNull);
      expect(upgraded!.startsWith(PasswordVerifier.pbkdf2Prefix), isTrue);
      // Both legacy entries should be cleared after migration.
      expect(legacy.hashes.containsKey(toxId), isFalse);
      expect(legacy.salts.containsKey(toxId), isFalse);
    });

    test('removePassword clears legacy plain-prefs entries too', () async {
      final legacy = FakeLegacyPasswordStore();
      legacy.hashes[toxId] = 'something';
      legacy.salts[toxId] = 'somesalt';
      final v = _buildVerifier(legacy: legacy);

      // Establish a current secure-storage entry too, so removePassword's
      // secure-delete branch succeeds and proceeds to the legacy cleanup.
      await v.setPassword(toxId, 'p');
      // setPassword already cleared the legacy entries on success.
      expect(legacy.hashes.containsKey(toxId), isFalse);
      expect(legacy.salts.containsKey(toxId), isFalse);

      // Re-seed and remove explicitly to exercise removePassword's cleanup.
      legacy.hashes[toxId] = 'something';
      legacy.salts[toxId] = 'somesalt';
      expect(await v.removePassword(toxId), isTrue);
      expect(legacy.hashes.containsKey(toxId), isFalse);
      expect(legacy.salts.containsKey(toxId), isFalse);
    });
  });

  group('PasswordVerifier — secure-storage write failure (legacy retained)',
      () {
    // Invariant pinned: a swallowed keychain failure during the PBKDF2
    // migration write must NOT lock the user out. The legacy verify must
    // still report success, and the legacy plain-prefs entries must remain
    // on disk so the next verify attempt can recover.

    test('salted-SHA256 legacy verify returns true and retains legacy '
        'entries when migration write is swallowed', () async {
      final legacy = FakeLegacyPasswordStore();
      const password = 'legacy-salted-pw';
      const saltB64 = 'c2FsdHk='; // base64 of "salty"
      legacy.hashes[toxId] = crypto.sha256
          .convert(utf8.encode('$saltB64$password'))
          .toString();
      legacy.salts[toxId] = saltB64;
      final throwing = ThrowingSecureStorageFacade();
      final v = _buildVerifier(legacy: legacy, secureStorage: throwing);

      expect(await v.verifyPassword(toxId, password), isTrue,
          reason: 'Legacy verify must still succeed even when the keychain '
              'refuses the PBKDF2 migration write — otherwise a sandboxed '
              'install would lock the user out of their own account.');
      expect(throwing.writeAttempts, greaterThan(0),
          reason: 'Verify path must have attempted the PBKDF2 migration '
              'write; ThrowingSecureStorageFacade simulates the swallow.');
      expect(legacy.hashes[toxId], isNotNull,
          reason: 'Legacy hash must be retained when the migration write '
              'failed — dropping it would destroy the only remaining copy '
              'of the credential.');
      expect(legacy.salts[toxId], isNotNull,
          reason: 'Legacy salt must be retained for the same reason.');
    });

    test('unsalted-SHA256 legacy verify returns true and retains legacy '
        'entries when migration write is swallowed', () async {
      final legacy = FakeLegacyPasswordStore();
      const password = 'legacy-pw';
      legacy.hashes[toxId] =
          crypto.sha256.convert(utf8.encode(password)).toString();
      // No salt — exercises the unsalted SHA-256 branch.
      final throwing = ThrowingSecureStorageFacade();
      final v = _buildVerifier(legacy: legacy, secureStorage: throwing);

      expect(await v.verifyPassword(toxId, password), isTrue,
          reason: 'Unsalted legacy verify must still succeed even when the '
              'PBKDF2 migration write is swallowed by secure storage.');
      expect(throwing.writeAttempts, greaterThan(0));
      expect(legacy.hashes[toxId], isNotNull,
          reason: 'Legacy hash must be retained when the migration write '
              'failed — otherwise the next verify has nothing to fall back '
              'to.');
    });
  });

  group('constantTimeEquals', () {
    test('equal strings compare true', () {
      expect(constantTimeEquals('abcdef', 'abcdef'), isTrue);
    });

    test('different lengths compare false up front (length is not the secret)',
        () {
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
    });

    test('same-length but different content compares false', () {
      expect(constantTimeEquals('abcdef', 'abcdeg'), isFalse);
    });

    test('empty strings compare true', () {
      expect(constantTimeEquals('', ''), isTrue);
    });
  });
}
