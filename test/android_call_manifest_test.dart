import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final manifestFile = File('$repoRoot/android/app/src/main/AndroidManifest.xml');

  test('Android phone-call foreground service declares required permissions',
      () async {
    expect(
      manifestFile.existsSync(),
      isTrue,
      reason: 'AndroidManifest.xml moved; update this regression test.',
    );
    final manifest = await manifestFile.readAsString();

    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_PHONE_CALL'),
    );
    expect(
      manifest,
      contains('android.permission.MANAGE_OWN_CALLS'),
      reason:
          'Android requires phoneCall foreground services to either declare '
          'MANAGE_OWN_CALLS or run as the default dialer.',
    );
    expect(
      manifest,
      contains('android:foregroundServiceType="dataSync|phoneCall"'),
    );
  });
}
