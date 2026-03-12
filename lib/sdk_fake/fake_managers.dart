import 'dart:async';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import 'fake_event_bus.dart';
import 'fake_models.dart';
import 'fake_im.dart';
import 'fake_uikit_core.dart';
import '../util/logger.dart';

class FakeConversationListener {
  FakeConversationListener({
    this.onNewConversation,
    this.onConversationChanged,
    this.onTotalUnreadChanged,
  });
  final void Function(List<FakeConversation> convs)? onNewConversation;
  final void Function(List<FakeConversation> convs)? onConversationChanged;
  final void Function(int total)? onTotalUnreadChanged;
}

class FakeConversationManager {
  FakeConversationManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeConversationListener> _listeners = [];
  StreamSubscription? _convSub;
  StreamSubscription? _unreadSub;
  Set<String> _pinned = {};

  void start() {
    Prefs.getPinned().then((value) {
      // Note: pinned contains normalized IDs (for C2C) or 'group_${normalizedGid}' (for groups)
      // Do NOT normalize here as it would break the 'group_xxx' format
      _pinned = value.toSet();
    });
    _convSub = _bus.on<FakeConversation>(FakeIM.topicConversation).listen((c) {
      for (final l in _listeners) {
        l.onNewConversation?.call([c]);
        l.onConversationChanged?.call([c]);
      }
    });
    _unreadSub = _bus.on<FakeUnreadTotal>(FakeIM.topicUnread).listen((u) {
      for (final l in _listeners) {
        l.onTotalUnreadChanged?.call(u.total);
      }
    });
  }

  void addListener(FakeConversationListener l) {
    _listeners.add(l);
  }

  Future<List<FakeConversation>> getConversationList() async {
    AppLogger.debug('[FakeConversationManager] getConversationList: START');
    final friends = await _ffi.getFriendList();
    AppLogger.debug(
        '[FakeConversationManager] getConversationList: Retrieved ${friends.length} friends from FFI');
    final pinned = await Prefs.getPinned();
    // Note: pinned contains normalized IDs (for C2C) or 'group_${normalizedGid}' (for groups)
    // We need to check against the original pinned set, not a normalized version
    // Filter out empty strings from legacy/corrupted data
    _pinned = pinned.where((s) => s.isNotEmpty).toSet();
    // Get pending friend applications (requests we sent that haven't been accepted yet)
    // These should not appear in the conversation list
    final pendingApps = await _ffi.getFriendApplications();
    final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();

    // Create a set of normalized friend IDs from the friend list
    // This is used to check if a pending application has been accepted
    final normalizedFriendIds =
        friends.map((f) => normalizeToxId(f.userId)).toSet();

    // Merge with locally persisted friends to ensure all friends with history are shown
    // But only if they are still in local persistence (not deleted)
    // Re-read local friends to ensure we have the latest state after deletion
    final currentLocalFriends = await Prefs.getLocalFriends();
    final currentNormalizedLocalFriends =
        currentLocalFriends.map((uid) => normalizeToxId(uid)).toSet();

    // Create a map of normalized IDs to friend info for easy lookup
    final friendMap =
        <String, ({String userId, String nickName, bool online})>{};
    for (final f in friends) {
      final normalizedId = normalizeToxId(f.userId);
      friendMap[normalizedId] =
          (userId: normalizedId, nickName: f.nickName, online: f.online);
    }

    // Add locally persisted friends that are not in service list
    // But only if they are still in current local persistence (not deleted)
    // Use currentNormalizedLocalFriends for iteration instead of normalizedLocalFriends
    // Load cached nicknames for offline friends
    for (final localId in currentNormalizedLocalFriends) {
      if (!friendMap.containsKey(localId)) {
        // Load nickname from cache for offline friends
        final cachedNick = await Prefs.getFriendNickname(localId);
        friendMap[localId] =
            (userId: localId, nickName: cachedNick ?? '', online: false);
      }
    }

    final list = <FakeConversation>[];
    final activityByC2cId = <String, DateTime?>{};
    final sortingMode = await Prefs.getFriendListSortingMode();
    AppLogger.debug(
        '[FakeConversationManager] getConversationList: Processing ${friendMap.length} friends from friendMap');
    for (final f in friendMap.values) {
      // Only filter out pending friend requests that haven't been accepted yet
      // If a friend is in the friend list (normalizedFriendIds), they have been accepted
      // and should appear in the conversation list even if they're still in pendingFriendIds
      final normalizedUserId = normalizeToxId(f.userId);
      if (pendingFriendIds.contains(f.userId) &&
          !normalizedFriendIds.contains(normalizedUserId)) {
        continue; // Filter out pending friend requests that haven't been accepted
      }
      // Load avatar path for conversation list and chat header
      final avatarPath = await Prefs.getFriendAvatarPath(f.userId);
      final activity = await Prefs.getFriendActivity(f.userId);
      activityByC2cId['c2c_${f.userId}'] = activity;
      // Check if this normalized user ID is in the pinned set
      // pinned contains normalized user IDs (without 'c2c_' prefix)
      final isPinned = _pinned.contains(normalizedUserId);
      if (isPinned || _pinned.isNotEmpty) {
        AppLogger.debug(
            '[FakeConversationManager] getConversationList: C2C - userId=${f.userId}, normalizedUserId=$normalizedUserId, isPinned=$isPinned, pinned set: ${_pinned.toList()}');
      }
      list.add(FakeConversation(
        conversationID: 'c2c_${f.userId}',
        title: f.nickName.isNotEmpty ? f.nickName : f.userId,
        faceUrl: avatarPath,
        unreadCount: _ffi.getUnreadOf(f.userId),
        isGroup: false,
        isPinned: isPinned,
      ));
    }
    // Get quit groups to filter them out
    final quitGroups = await Prefs.getQuitGroups();

    for (final gid in _ffi.knownGroups) {
      // Skip groups that the user has quit
      if (quitGroups.contains(gid)) {
        AppLogger.debug(
            '[FakeConversationManager] getConversationList: Skipping quit group: $gid');
        continue;
      }
      // Always get the latest group name and avatar from Prefs to ensure consistency
      final savedName = await Prefs.getGroupName(gid);
      final savedAvatar = await Prefs.getGroupAvatar(gid);
      // Use saved name if available and not empty, otherwise fall back to group ID
      final name =
          (savedName != null && savedName.isNotEmpty) ? savedName : gid;
      // Check if this group is pinned using 'group_${normalizedGid}' format
      // to match what setPinned stores
      final normalizedGid = normalizeToxId(gid);
      final groupPinnedKey = 'group_$normalizedGid';
      final isPinned = _pinned.contains(groupPinnedKey);
      if (isPinned || _pinned.isNotEmpty) {
        AppLogger.debug(
            '[FakeConversationManager] getConversationList: Group - gid=$gid, normalizedGid=$normalizedGid, groupPinnedKey=$groupPinnedKey, isPinned=$isPinned, pinned set: ${_pinned.toList()}');
      }
      list.add(
        FakeConversation(
          conversationID: 'group_$gid',
          title: name,
          faceUrl: savedAvatar,
          unreadCount: _ffi.getUnreadOf(gid),
          isGroup: true,
          isPinned: isPinned,
        ),
      );
    }
    // Sort: pinned first, then by sorting mode (activity = most recent first, name = by title)
    list.sort((a, b) {
      final aPinned = a.isPinned ? 0 : 1;
      final bPinned = b.isPinned ? 0 : 1;
      if (aPinned != bPinned) return aPinned.compareTo(bPinned);
      if (sortingMode == 'activity') {
        final aMs = a.conversationID.startsWith('c2c_')
            ? (activityByC2cId[a.conversationID]?.millisecondsSinceEpoch ?? 0)
            : 0;
        final bMs = b.conversationID.startsWith('c2c_')
            ? (activityByC2cId[b.conversationID]?.millisecondsSinceEpoch ?? 0)
            : 0;
        final cmp = bMs.compareTo(aMs);
        if (cmp != 0) return cmp;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    AppLogger.log(
        '[FakeConversationManager] getConversationList: END - Returning ${list.length} conversations (${list.where((c) => !c.isGroup).length} C2C, ${list.where((c) => c.isGroup).length} groups), sort=$sortingMode');
    return list;
  }

  Future<void> setPinned(String conversationID, bool pin) async {
    AppLogger.debug(
        '[FakeConversationManager] setPinned: START - conversationID=$conversationID, pin=$pin');
    // Validate conversationID - reject empty or invalid IDs
    if (conversationID.isEmpty ||
        conversationID == 'c2c_' ||
        conversationID == 'group_') {
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Invalid conversationID, returning early');
      return;
    }

    final friends = await _ffi.getFriendList();
    String normalizedStoreKey;

    if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      // Validate group ID
      if (gid.isEmpty) {
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Empty group ID, returning early');
        return;
      }
      // For groups, use 'group_${normalizedGid}' format to match getConversationList
      final normalizedGid = normalizeToxId(gid);
      normalizedStoreKey = 'group_$normalizedGid';
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Group - gid=$gid, normalizedGid=$normalizedGid, normalizedStoreKey=$normalizedStoreKey');

      final next = {..._pinned};
      if (pin) {
        next.add(normalizedStoreKey);
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}');
      } else {
        next.remove(normalizedStoreKey);
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}');
      }
      _pinned = next;
      await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}');

      // Always get the latest group name from Prefs to ensure consistency
      final savedName = await Prefs.getGroupName(gid);
      final name =
          (savedName != null && savedName.isNotEmpty) ? savedName : gid;
      final conv = FakeConversation(
        conversationID: conversationID,
        title: name,
        faceUrl: null,
        unreadCount: _ffi.getUnreadOf(gid),
        isGroup: true,
        isPinned: pin,
      );
      _bus.emit(FakeIM.topicConversation, conv);
      // Trigger conversation list refresh
      await FakeUIKit.instance.im?.refreshConversations();
      return;
    }

    // For C2C conversations, extract user ID and normalize
    final storeKey = conversationID.startsWith('c2c_')
        ? conversationID.substring(4)
        : conversationID;
    // Validate storeKey - reject empty keys
    if (storeKey.isEmpty) {
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Empty storeKey, returning early');
      return;
    }

    // Normalize the storeKey to ensure consistency with getConversationList
    // which uses normalized IDs when checking pinned.contains()
    normalizedStoreKey = normalizeToxId(storeKey);
    AppLogger.debug(
        '[FakeConversationManager] setPinned: C2C - storeKey=$storeKey, normalizedStoreKey=$normalizedStoreKey');

    final next = {..._pinned};
    if (pin) {
      next.add(normalizedStoreKey);
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}');
    } else {
      next.remove(normalizedStoreKey);
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}');
    }
    _pinned = next;
    await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
    AppLogger.debug(
        '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}');
    // Use normalizedStoreKey for consistency
    final id = normalizedStoreKey;
    // Validate user ID
    if (id.isEmpty) {
      return;
    }
    // Find friend by comparing normalized IDs
    final friend = friends.firstWhere(
      (f) => normalizeToxId(f.userId) == id,
      orElse: () => (userId: id, nickName: id, status: '', online: false),
    );
    final conv = FakeConversation(
      conversationID: 'c2c_$id',
      title: friend.nickName.isNotEmpty ? friend.nickName : friend.userId,
      faceUrl: null,
      unreadCount: _ffi.getUnreadOf(id),
      isGroup: false,
      isPinned: pin,
    );
    _bus.emit(FakeIM.topicConversation, conv);
    // Trigger conversation list refresh
    await FakeUIKit.instance.im?.refreshConversations();
  }

  void dispose() {
    _convSub?.cancel();
    _unreadSub?.cancel();
    _listeners.clear();
    _pinned.clear();
  }
}

class FakeMessageListener {
  FakeMessageListener({this.onRecvNewMessage, this.onTyping});
  final void Function(FakeMessage msg)? onRecvNewMessage;
  final void Function(FakeTypingEvent typing)? onTyping;
}

class FakeMessageManager {
  FakeMessageManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeMessageListener> _listeners = [];
  StreamSubscription? _msgSub;
  StreamSubscription? _typingSub;

  /// In-memory local messages (e.g. call records) keyed by normalized user ID.
  /// These are merged into getHistory() results since they aren't in Tox history.
  final Map<String, List<FakeMessage>> _localMessages = {};

  /// Return the newest [count] items from an ascending list.
  /// If [count] is non-positive or larger than the list length, return all.
  static List<T> takeLatestWindow<T>(List<T> items, int count) {
    if (count <= 0 || count >= items.length) {
      return List<T>.from(items);
    }
    return List<T>.from(items.sublist(items.length - count));
  }

  void start() {
    _msgSub = _bus.on<FakeMessage>(FakeIM.topicMessage).listen((m) {
      // Update friend activity for "sort by activity" (C2C only; sender is the peer)
      if (m.conversationID.startsWith('c2c_') &&
          m.fromUser != _ffi.selfId &&
          m.fromUser.isNotEmpty) {
        Prefs.setFriendActivity(m.fromUser, DateTime.now());
      }
      for (final l in _listeners) {
        l.onRecvNewMessage?.call(m);
      }
    });
    _typingSub = _bus.on<FakeTypingEvent>(FakeIM.topicTyping).listen((t) {
      for (final l in _listeners) {
        l.onTyping?.call(t);
      }
    });
  }

  void addListener(FakeMessageListener l) {
    _listeners.add(l);
  }

  /// Add a locally generated message (e.g. call record) that should appear in
  /// history but is not stored in Tox.  [userID] is the remote peer's ID.
  void addLocalMessage(String userID, FakeMessage msg) {
    final key = normalizeToxId(userID);
    _localMessages.putIfAbsent(key, () => <FakeMessage>[]).add(msg);
    AppLogger.log(
        '[FakeMessageManager] addLocalMessage: userID=$userID, key=$key, msgID=${msg.msgID}, total=${_localMessages[key]!.length}');
  }

  Future<List<FakeMessage>> getHistory(String conversationID,
      {int count = 50}) async {
    String id;
    if (conversationID.startsWith('c2c_')) {
      id = conversationID.substring(4);
      // Don't normalize here - let FfiChatService.getHistory handle normalization
      // This ensures we use the same normalization logic as when saving history
      id = id.trim();
    } else if (conversationID.startsWith('group_')) {
      id = conversationID.substring(6);
    } else {
      id = conversationID;
    }
    AppLogger.log(
        '[FakeMessageManager] getHistory called: conversationID=$conversationID, id=$id');
    final hist = _ffi.getHistory(id);
    AppLogger.log(
        '[FakeMessageManager] getHistory returned ${hist.length} messages for id=$id');
    // Sort by timestamp ascending (oldest first, newest last) - UIKit pattern
    // DO NOT reverse here! UIKit's reverse ListView will handle the display order
    final sorted = hist
        .map((h) => FakeMessage(
              msgID: h.msgID ??
                  '${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}',
              conversationID: conversationID,
              fromUser: h.fromUserId,
              text: h.text,
              timestampMs: h.timestamp.millisecondsSinceEpoch,
              filePath: h.filePath,
              fileName: h.fileName, // Pass original file name
              mediaKind: h.mediaKind,
              isPending: h.isPending,
              isReceived: h.isReceived,
              isRead: h.isRead,
            ))
        .toList();

    // Merge in locally generated messages (e.g. call records) for this user
    final normalizedId = normalizeToxId(id);
    final localMsgs = _localMessages[normalizedId];
    if (localMsgs != null && localMsgs.isNotEmpty) {
      AppLogger.log(
          '[FakeMessageManager] getHistory: merging ${localMsgs.length} local messages for $normalizedId');
      sorted.addAll(localMsgs);
    }

    sorted.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    // Return all messages (or the newest [count] if specified)
    // UIKit will handle pagination if needed
    return takeLatestWindow(sorted, count);
  }

  Future<void> sendText(String conversationID, String text) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      // Always call _ffi.sendText - it will handle offline messages by creating pending messages
      // This ensures messages are displayed in the chat window even when friend is offline
      await _ffi.sendText(uid, text);

      // Get the message from history (which includes pending messages for offline friends)
      final history = _ffi.getHistory(uid);
      final lastMsg = history.isNotEmpty ? history.last : null;

      // If message was created (either sent or pending), emit it via bus for UIKit
      if (lastMsg != null && lastMsg.text == text && lastMsg.isSelf) {
        Prefs.setFriendActivity(uid, DateTime.now());
        final msgID =
            lastMsg.msgID ?? '${DateTime.now().microsecondsSinceEpoch}';
        final msg = FakeMessage(
          msgID: msgID,
          conversationID: conversationID,
          fromUser: _ffi.selfId,
          text: text,
          timestampMs: lastMsg.timestamp.millisecondsSinceEpoch,
          isPending: lastMsg
              .isPending, // Use actual pending status from FfiChatService
          isReceived: lastMsg.isReceived,
          isRead: lastMsg.isRead,
        );
        _bus.emit(FakeIM.topicMessage, msg);
      }
    } else if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      await _ffi.sendGroupText(gid, text);
      // Don't emit local echo for group messages - Tox will echo it back via ffi.messages.listen
      // This prevents duplicate messages in the chat window
    }
  }

  Future<void> sendFile(String conversationID, String filePath) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      Prefs.setFriendActivity(uid, DateTime.now());
      await _ffi.sendFile(uid, filePath);
      // Note: Local echo will be emitted by FfiChatService.sendFile via ffi.messages stream
      // No need to emit here to avoid duplicates
    } else if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      await _ffi.sendGroupFile(gid, filePath);
      // Don't emit local echo for group messages - Tox will echo it back via ffi.messages.listen
      // This prevents duplicate messages in the chat window
    }
  }

  /// Delete messages by their IDs
  /// This is called by UIKit when user deletes messages
  Future<void> deleteMessages(List<String> msgIDs) async {
    await _ffi.deleteMessages(msgIDs);
    // Emit a message deletion event to notify listeners
    // Note: We don't have a specific deletion event, but the UI should refresh
    // The FakeChatMessageProvider will handle the UI update by re-emitting the message list
  }

  /// Send message read receipts
  /// This is called by UIKit when messages are viewed
  Future<void> sendMessageReadReceipts(List<String> msgIDList,
      {String? userID, String? groupID}) async {
    try {
      if (groupID != null) {
        // For group messages, send read receipt to the group
        for (final msgID in msgIDList) {
          await _ffi.markMessageAsRead(groupID, msgID, groupID: groupID);
        }
      } else if (userID != null) {
        // For C2C messages, send read receipt to the user
        for (final msgID in msgIDList) {
          await _ffi.markMessageAsRead(userID, msgID);
        }
      } else {
        throw Exception('Either userID or groupID must be provided');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get list of users who received a group message
  /// This is called by UIKit to display message receivers
  List<String> getMessageReceivers(String msgID) {
    return _ffi.getMessageReceivers(msgID);
  }

  /// Get count of users who received a group message
  /// This is called by UIKit to display message receiver count
  int getMessageReceiverCount(String msgID) {
    return _ffi.getMessageReceiverCount(msgID);
  }

  void dispose() {
    _msgSub?.cancel();
    _typingSub?.cancel();
    _listeners.clear();
  }
}

class FakeContactListener {
  FakeContactListener({this.onFriendList, this.onFriendApps});
  final void Function(List<FakeUser> users)? onFriendList;
  final void Function(List<FakeFriendApplication> apps)? onFriendApps;
}

class FakeContactManager {
  FakeContactManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeContactListener> _listeners = [];
  StreamSubscription? _friendsSub;
  StreamSubscription? _appsSub;

  void start() {
    _friendsSub = _bus.on<List<FakeUser>>(FakeIM.topicContacts).listen((list) {
      for (final l in _listeners) {
        l.onFriendList?.call(list);
      }
    });
    _appsSub = _bus
        .on<List<FakeFriendApplication>>(FakeIM.topicFriendApps)
        .listen((list) {
      for (final l in _listeners) {
        l.onFriendApps?.call(list);
      }
    });
  }

  void addListener(FakeContactListener l) {
    _listeners.add(l);
  }

  Future<List<FakeUser>> getFriendList() async {
    final friends = await _ffi.getFriendList();
    return friends
        .map((f) => FakeUser(
            userID: f.userId,
            nickName: f.nickName,
            status: f.status,
            online: f.online))
        .toList();
  }

  void dispose() {
    _friendsSub?.cancel();
    _appsSub?.cancel();
    _listeners.clear();
  }
}
