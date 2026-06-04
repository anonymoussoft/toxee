import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  test('L3 harness environment snapshot exposes isolation prefixes', () {
    final snapshot =
        debugL3HarnessEnvironmentSnapshotForTests(const <String, String>{
          'TOXEE_SHARED_PREFS_PREFIX': 'toxee_a.',
          'TOXEE_APP_SUPPORT_DIR': '/tmp/toxee/A',
          'TOXEE_TCCF_GLOBAL_SUBDIR': 'multi_instance/A/tccfglobal',
        });

    expect(snapshot['sharedPrefsPrefix'], 'toxee_a.');
    expect(snapshot['appSupportDirOverride'], '/tmp/toxee/A');
    expect(snapshot['tccfGlobalSubdir'], 'multi_instance/A/tccfglobal');
  });
}
