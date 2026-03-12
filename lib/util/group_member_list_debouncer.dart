// Debouncer to prevent duplicate loadGroupMemberList calls
import 'dart:async';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';

class GroupMemberListDebouncer {
  static final GroupMemberListDebouncer _instance = GroupMemberListDebouncer._internal();
  factory GroupMemberListDebouncer() => _instance;
  GroupMemberListDebouncer._internal();

  // Track loading state per groupID
  final Map<String, bool> _loadingGroups = {};
  // Track last load time per groupID to prevent rapid successive calls
  final Map<String, DateTime> _lastLoadTime = {};
  // Track pending futures to reuse them
  final Map<String, Future<List<V2TimGroupMemberFullInfo?>>> _pendingLoads = {};
  
  // Minimum time between loads for the same group (2 seconds to prevent rapid loops)
  static const Duration _minLoadInterval = Duration(seconds: 2);

  Future<List<V2TimGroupMemberFullInfo?>> loadGroupMemberList({
    required String groupID,
    required bool loadGroupAdminAndOwnerOnly,
    String nextSeq = "0",
  }) async {
    // Check if already loading for this group
    if (_loadingGroups[groupID] == true) {
      // Return pending future if exists
      if (_pendingLoads.containsKey(groupID)) {
        return _pendingLoads[groupID]!;
      }
    }

    // Check if we recently loaded this group
    final lastLoadTime = _lastLoadTime[groupID];
    if (lastLoadTime != null) {
      final timeSinceLastLoad = DateTime.now().difference(lastLoadTime);
      if (timeSinceLastLoad < _minLoadInterval) {
        // Too soon, return cached data if available
        final cachedList = TencentCloudChat.instance.dataInstance.groupProfile
            .getGroupMemberList(groupID);
        if (cachedList.isNotEmpty) {
          // Return cached data to prevent duplicate calls
          return cachedList;
        }
        // If no cache, wait a bit and try again
        await Future.delayed(_minLoadInterval - timeSinceLastLoad);
      }
    }

    // Mark as loading
    _loadingGroups[groupID] = true;
    _lastLoadTime[groupID] = DateTime.now();

    // Create and store the future
    final loadFuture = TencentCloudChat.instance.dataInstance.groupProfile
        .loadGroupMemberList(
      groupID: groupID,
      loadGroupAdminAndOwnerOnly: loadGroupAdminAndOwnerOnly,
      nextSeq: nextSeq,
    );

    _pendingLoads[groupID] = loadFuture;

    try {
      final result = await loadFuture;
      return result;
    } finally {
      // Clear loading state after a delay to prevent rapid successive calls
      Future.delayed(_minLoadInterval, () {
        _loadingGroups[groupID] = false;
        _pendingLoads.remove(groupID);
      });
    }
  }

  void clear() {
    _loadingGroups.clear();
    _lastLoadTime.clear();
    _pendingLoads.clear();
  }
}
