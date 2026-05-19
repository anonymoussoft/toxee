import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'logger.dart';
import 'prefs.dart';
import 'tox_utils.dart';

/// Cleans up per-friend assets that would otherwise leak when a friend is
/// deleted on the Tox side. See A8 in `docs/designs/local-storage-review-2026-05-18.md`.
///
/// The upstream `FfiChatService.deleteFriend` removes the prefs friend list
/// entry and clears chat history but **does not** delete the on-disk avatar
/// file at `<avatars>/friend_<id>_avatar_<ts>.<ext>` nor the
/// `avatar_hash_<friendId>` / `friend_avatar_path_<friendId>` prefs keys.
/// Over time those orphan files accumulate. We can't fix it in tim2tox
/// without bumping that vendored dep, so the cleanup happens client-side
/// from the FakeIM `topicFriendDeleted` event.
abstract final class FriendAssetCleanup {
  FriendAssetCleanup._();

  /// Delete every asset belonging to [friendId] for the currently-active
  /// account. Matches avatar files whose basename starts with
  /// `friend_<id>_avatar_` for both the normalized 64-char public key form
  /// and the raw input form (so files saved under either are caught).
  ///
  /// Best-effort: per-file errors are logged but never thrown so a single
  /// unreadable path does not stop the rest of the cleanup. Safe to call
  /// repeatedly.
  static Future<void> deleteAllAssetsFor(String friendId) async {
    if (friendId.isEmpty) return;
    final normalized = normalizeToxId(friendId);
    int filesDeleted = 0;
    try {
      final toxId = await Prefs.getCurrentAccountToxId();
      if (toxId == null || toxId.isEmpty) {
        AppLogger.warn(
            '[FriendAssetCleanup] no current account; skipping cleanup for $friendId');
      } else {
        final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
        final avatarsDir = Directory(avatarsPath);
        if (await avatarsDir.exists()) {
          // The on-disk naming is `friend_<id>_avatar_<ts><ext>` where <id>
          // is whatever caller of FfiChatService passed. Match both
          // normalized and raw to cover historical and current writes.
          final prefixes = <String>{
            'friend_${normalized}_avatar_',
            if (friendId != normalized) 'friend_${friendId}_avatar_',
          };
          await for (final entity in avatarsDir.list(followLinks: false)) {
            if (entity is! File) continue;
            final base = p.basename(entity.path);
            final match = prefixes.any(base.startsWith);
            if (!match) continue;
            try {
              await entity.delete();
              filesDeleted++;
            } catch (e, st) {
              AppLogger.logError(
                  '[FriendAssetCleanup] failed to delete ${entity.path}',
                  e,
                  st);
            }
          }
        }
      }
    } catch (e, st) {
      AppLogger.logError(
          '[FriendAssetCleanup] avatar-file cleanup failed for $friendId',
          e,
          st);
    }

    // Prefs cleanup runs regardless of file-system outcome; the keys are
    // small and removing them is harmless even when no file existed.
    try {
      await Prefs.removeFriendAvatarHash(normalized);
      if (friendId != normalized) {
        await Prefs.removeFriendAvatarHash(friendId);
      }
      // `setFriendAvatarPath(_, null)` removes the friend_avatar_path_<id>
      // scoped key (see Prefs.setFriendAvatarPath).
      await Prefs.setFriendAvatarPath(normalized, null);
      if (friendId != normalized) {
        await Prefs.setFriendAvatarPath(friendId, null);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[FriendAssetCleanup] prefs cleanup failed for $friendId', e, st);
    }

    AppLogger.info(
        '[FriendAssetCleanup] cleaned up friend=$friendId (filesDeleted=$filesDeleted)');
  }
}
