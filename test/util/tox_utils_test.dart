import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/tox_utils.dart';

void main() {
  group('toToxPublicKey', () {
    const pubKey =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const fullId =
        // 64 hex pubkey ............................................
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        // 8 hex nospam + 4 hex checksum = 12 chars → total 76
        'CAFEBABE0000';

    test('strips Tox ID nospam+checksum (76 → 64)', () {
      final out = toToxPublicKey(fullId);
      expect(out.length, 64);
      expect(out, pubKey.toLowerCase());
    });

    test('returns a bare 64-char public key unchanged (lowercased)', () {
      expect(toToxPublicKey(pubKey), pubKey.toLowerCase());
    });

    test('trims whitespace and lowercases', () {
      expect(toToxPublicKey('  ABCD  '), 'abcd');
    });

    test('does not throw on short / non-hex input', () {
      expect(toToxPublicKey(''), '');
      expect(toToxPublicKey('group_42'), 'group_42');
    });

    test('truncates strings longer than 64 that are not 76 chars', () {
      final long = 'a' * 100;
      expect(toToxPublicKey(long).length, 64);
    });
  });

  group('normalizeToxId (legacy alias)', () {
    test('agrees with toToxPublicKey for 76-char IDs', () {
      final full = 'b' * 64 + 'CAFEBABE0000';
      expect(normalizeToxId(full), toToxPublicKey(full));
    });
  });
}
