// Guards the L3 seed-account marker (Prefs.{add,get,remove}L3SeedToxId).
// The marker grants the debug L3 mutating-tool surface, so its lifecycle must
// be exact: authorization is by 64-hex public-key prefix, and revocation
// (on account delete) MUST hit even when the delete uses a different
// representation (64 vs 76 hex) of the same account — codex F2.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pk = 'AABBCCDDEEFF00112233445566778899'
      'AABBCCDDEEFF00112233445566778899'; // 64 hex
  const full76 = '$pk' '1A2B3C4D5DBE'; // 64 + nospam/checksum-ish (76 hex)

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  test('add stores the 64-hex public-key prefix (not the 76-char form)', () async {
    await Prefs.addL3SeedToxId(full76);
    final ids = await Prefs.getL3SeedToxIds();
    expect(ids, contains(pk));
    expect(ids.any((s) => s.length > 64), isFalse);
  });

  test('add is idempotent across representations + case', () async {
    await Prefs.addL3SeedToxId(pk);
    await Prefs.addL3SeedToxId(full76);
    await Prefs.addL3SeedToxId(pk.toLowerCase());
    expect((await Prefs.getL3SeedToxIds()).length, 1);
  });

  test('remove with the 76-char form revokes a marker added as 64-char',
      () async {
    await Prefs.addL3SeedToxId(pk);
    await Prefs.removeL3SeedToxId(full76); // different representation
    expect(await Prefs.getL3SeedToxIds(), isEmpty);
  });

  test('remove with the 64-char form revokes a marker added as 76-char',
      () async {
    await Prefs.addL3SeedToxId(full76);
    await Prefs.removeL3SeedToxId(pk);
    expect(await Prefs.getL3SeedToxIds(), isEmpty);
  });

  test('removeAccount revokes the marker (grant cannot outlive the account)',
      () async {
    await Prefs.addL3SeedToxId(full76);
    await Prefs.removeAccount(pk); // delete by public key
    expect(await Prefs.getL3SeedToxIds(), isEmpty);
  });

  test('empty input is a no-op', () async {
    await Prefs.addL3SeedToxId('');
    await Prefs.removeL3SeedToxId('   ');
    expect(await Prefs.getL3SeedToxIds(), isEmpty);
  });
}
