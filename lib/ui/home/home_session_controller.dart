import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../util/prefs.dart';
import '../../util/tox_utils.dart';

/// Session-scoped business logic for [HomePage]: contact load and sync.
/// Keeps UI layer thin by moving friend list merge and persisted-friends sync here.
class HomeSessionController {
  HomeSessionController({required this.service});

  final FfiChatService service;

  /// Loads friend list from service, merges with locally persisted friends,
  /// and returns data for the widget to setState.
  Future<({List<({String userId, String nickName, bool online, String status})> friends, Set<String> localFriends})> loadContacts() async {
    final list = await service.getFriendList();
    await Future.delayed(const Duration(milliseconds: 100));
    final localFriendsToUse = await Prefs.getLocalFriends();

    final existingIds = list.map((e) => normalizeToxId(e.userId)).toSet();
    final merged = <({String userId, String nickName, bool online, String status})>[...list];
    final normalizedLocalFriends = localFriendsToUse.map((uid) => normalizeToxId(uid)).toSet();

    for (final normalizedUid in normalizedLocalFriends) {
      if (!existingIds.contains(normalizedUid)) {
        final cachedNick = await Prefs.getFriendNickname(normalizedUid);
        final cachedStatus = await Prefs.getFriendStatusMessage(normalizedUid);
        merged.add((
          userId: normalizedUid,
          nickName: cachedNick ?? '',
          online: false,
          status: cachedStatus ?? '',
        ));
      }
    }

    return (friends: merged, localFriends: localFriendsToUse);
  }

  /// Re-adds friends that are in local persistence but not in Tox so Tox can send online status.
  Future<void> syncPersistedFriendsToTox() async {
    try {
      final persistedFriends = await Prefs.getLocalFriends();
      if (persistedFriends.isEmpty) return;

      final toxFriends = await service.getFriendList();
      final toxFriendIds = toxFriends.map((f) {
        final id = f.userId.trim();
        return id.length > 64 ? id.substring(0, 64) : id;
      }).toSet();

      final friendsToReAdd = <String>[];
      for (final persistedId in persistedFriends) {
        final normalizedId = persistedId.trim();
        final actualId = normalizedId.length > 64 ? normalizedId.substring(0, 64) : normalizedId;
        if (!toxFriendIds.contains(actualId)) {
          friendsToReAdd.add(actualId);
        }
      }

      if (friendsToReAdd.isEmpty) return;

      for (final friendId in friendsToReAdd) {
        try {
          await service.acceptFriendRequest(friendId);
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (_) {}
      }
    } catch (_) {}
  }
}
