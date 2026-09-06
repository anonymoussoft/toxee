// Contract test for `IrcAppManager.nativeLibraryProbe()`, the capability gate
// behind the L3 `l3_irc_native_library_probe` seam. The real-UI
// `irc_join_channel_loopback_live` case SKIPs on `available == false` and runs
// the live JOIN otherwise, so the probe must (1) never throw for a missing or
// unloadable library, (2) name the platform file it looked for, and (3) carry
// the loader's message exactly when — and only when — it reports unavailable.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/irc_app_manager.dart';

void main() {
  test('probe names the platform library and never throws', () {
    final probe = IrcAppManager().nativeLibraryProbe();
    final expectedName = Platform.isWindows
        ? 'libirc_client.dll'
        : (Platform.isMacOS || Platform.isIOS)
        ? 'libirc_client.dylib'
        : 'libirc_client.so';
    expect(probe.path, endsWith(expectedName));
    if (probe.available) {
      expect(probe.error, isNull);
    } else {
      expect(probe.error, isNotNull);
      expect(probe.error, isNotEmpty);
    }
  });

  test('an unloadable library is reported as unavailable, not thrown', () {
    final bogus =
        '${Directory.systemTemp.path}/definitely-missing-libirc_client.so';
    final probe = IrcAppManager().nativeLibraryProbe(libraryPath: bogus);
    expect(probe.available, isFalse);
    expect(probe.path, bogus);
    expect(probe.error, isNotNull);
    expect(probe.error, isNotEmpty);
  });
}
