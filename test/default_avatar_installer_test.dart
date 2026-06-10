import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/default_avatar_installer.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Missing fake asset for $key');
    }
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultAvatarInstaller', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });

    tearDown(() async {
      await env.dispose();
      AppPaths.debugApplicationSupportOverride = null;
    });

    test(
      'installs the bundled default personal avatar into the account avatar directory',
      () async {
        const toxId =
            '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF001122334455';
        final bundle = _FakeAssetBundle({
          DefaultAvatarInstaller.defaultUserAsset: Uint8List.fromList(<int>[
            1,
            2,
            3,
            4,
            5,
          ]),
        });

        await Prefs.setCurrentAccountToxId(toxId);

        final avatarPath =
            await DefaultAvatarInstaller.installDefaultUserAvatar(
              toxId: toxId,
              bundle: bundle,
            );

        final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
        expect(avatarPath, startsWith(avatarsDir));
        expect(p.basename(avatarPath), 'avatar_${toxId}_default.png');
        expect(await File(avatarPath).exists(), isTrue);
        expect(await File(avatarPath).readAsBytes(), <int>[1, 2, 3, 4, 5]);
      },
    );

    test(
      'installs the bundled default group avatar into the account avatar directory and persists the pref',
      () async {
        const toxId =
            '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF001122334455';
        const groupId = 'group-alpha';
        final bundle = _FakeAssetBundle({
          DefaultAvatarInstaller.defaultGroupAsset: Uint8List.fromList(<int>[
            9,
            8,
            7,
            6,
          ]),
        });

        await Prefs.setCurrentAccountToxId(toxId);

        final avatarPath =
            await DefaultAvatarInstaller.installDefaultGroupAvatar(
              groupId: groupId,
              toxId: toxId,
              bundle: bundle,
            );
        await Prefs.setGroupAvatar(groupId, avatarPath);

        final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
        expect(avatarPath, startsWith(avatarsDir));
        expect(p.basename(avatarPath), 'group_group-alpha_default.png');
        expect(await File(avatarPath).exists(), isTrue);
        expect(await File(avatarPath).readAsBytes(), <int>[9, 8, 7, 6]);
        expect(await Prefs.getGroupAvatar(groupId), avatarPath);
      },
    );
  });
}
