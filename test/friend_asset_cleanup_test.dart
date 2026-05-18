// A8: FriendAssetCleanup must purge on-disk avatar files and avatar-hash /
// friend_avatar_path prefs keys when a friend is deleted. Without this, the
// per-friend avatars directory grows unbounded over time because
// tim2tox's FfiChatService.deleteFriend does not handle these.
//
// Strategy: seed the per-account avatars dir with dummy files (matching
// both the normalized 64-char form and a 76-char form), seed the avatar
// hash + path prefs keys for the friend, run the cleanup, and assert
// every seeded asset is gone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/friend_asset_cleanup.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

const _selfToxId =
    'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';

void main() {
  group('FriendAssetCleanup.deleteAllAssetsFor (A8)', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      await Prefs.setCurrentAccountToxId(_selfToxId);
    });

    tearDown(() async {
      await env.dispose();
    });

    test('no-op when friendId is empty', () async {
      await FriendAssetCleanup.deleteAllAssetsFor('');
      // Nothing to assert beyond "no throw".
    });

    test('deletes avatar files (normalized + raw) and clears prefs',
        () async {
      const friendId =
          'FFEEDDCCBBAA99887766554433221100FFEEDDCCBBAA99887766554433221100';
      // Construct a 76-char "raw" variant by appending 12 hex chars.
      const friendIdRaw = '${friendId}AABBCCDD1122';

      // Seed the per-account avatars directory.
      final avatarsPath = await AppPaths.getAccountAvatarsPath(_selfToxId);
      await Directory(avatarsPath).create(recursive: true);
      final keep = File(p.join(avatarsPath, 'self_avatar_123.png'));
      final other = File(p.join(avatarsPath,
          'friend_DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF_avatar_99.png'));
      final f1 = File(p.join(avatarsPath, 'friend_${friendId}_avatar_111.png'));
      final f2 = File(p.join(avatarsPath, 'friend_${friendId}_avatar_222.jpg'));
      final fRaw =
          File(p.join(avatarsPath, 'friend_${friendIdRaw}_avatar_333.png'));
      for (final f in [keep, other, f1, f2, fRaw]) {
        await f.writeAsBytes([0]);
      }

      // Seed prefs keys we expect to be removed.
      await Prefs.setFriendAvatarHash(friendId, 'hash-abc');
      await Prefs.setFriendAvatarPath(friendId, '/some/path.png');

      // Sanity: hash + path are readable before cleanup.
      expect(await Prefs.getFriendAvatarHash(friendId), 'hash-abc');
      expect(await Prefs.getFriendAvatarPath(friendId), '/some/path.png');

      // Cleanup using the raw form — the helper must handle both raw and
      // normalized lookups internally.
      await FriendAssetCleanup.deleteAllAssetsFor(friendIdRaw);

      // Friend's own avatar files are gone.
      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isFalse);
      expect(await fRaw.exists(), isFalse);
      // Unrelated files survive.
      expect(await keep.exists(), isTrue,
          reason: 'self avatar must not be deleted');
      expect(await other.exists(), isTrue,
          reason: 'a different friend\'s avatar must not be deleted');

      // Prefs keys are gone.
      expect(await Prefs.getFriendAvatarHash(friendId), isNull);
      expect(await Prefs.getFriendAvatarPath(friendId), isNull);
    });

    test('idempotent: running twice does not throw', () async {
      const friendId =
          '1111111111111111111111111111111111111111111111111111111111111111';
      // No files, no prefs entries — cleanup should be a no-op.
      await FriendAssetCleanup.deleteAllAssetsFor(friendId);
      await FriendAssetCleanup.deleteAllAssetsFor(friendId);
    });

    test('survives when avatars dir does not exist yet', () async {
      const friendId =
          '2222222222222222222222222222222222222222222222222222222222222222';
      // Don't create the avatars dir.
      await FriendAssetCleanup.deleteAllAssetsFor(friendId);
      // Hash key still removed safely.
      expect(await Prefs.getFriendAvatarHash(friendId), isNull);
    });
  });
}
