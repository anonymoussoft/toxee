import 'dart:ui';

/// Core/network-related preferences (bootstrap, server id, LAN).
abstract class ICorePrefs {
  Future<String?> getServerId();
  Future<void> setServerId(String value);
  Future<({String host, int port, String pubkey})?> getCurrentBootstrapNode();
  Future<void> setCurrentBootstrapNode(String host, int port, String pubkey);
  Future<void> clearCurrentBootstrapNode();
  Future<String> getBootstrapNodeMode();
  Future<void> setBootstrapNodeMode(String mode);
  Future<int> getLanBootstrapPort();
  Future<void> setLanBootstrapPort(int port);
  Future<bool> getLanBootstrapServiceRunning();
  Future<void> setLanBootstrapServiceRunning(bool running);
}

/// Friend/contact and group list preferences.
abstract class IFriendPrefs {
  Future<Set<String>> getPinned();
  Future<void> setPinned(Set<String> peers);
  Future<Set<String>> getMuted();
  Future<void> setMuted(Set<String> peers);
  Future<Set<String>> getLocalFriends();
  Future<void> setLocalFriends(Set<String> ids);
  Future<Set<String>> getGroups();
  Future<void> setGroups(Set<String> groups);
  Future<Set<String>> getQuitGroups();
  Future<void> setQuitGroups(Set<String> groups);
  Future<String?> getGroupName(String groupId);
  Future<void> setGroupName(String groupId, String name);
  Future<String?> getFriendNickname(String userId);
  Future<void> setFriendNickname(String userId, String? nickname);
  Future<String?> getFriendAvatarPath(String userId);
  Future<void> setFriendAvatarPath(String userId, String? path);
}

/// UI state: theme, locale, profile, window/splitter, drafts.
abstract class IUIPrefs {
  Future<String> getThemeMode();
  Future<void> setThemeMode(String mode);
  Future<String?> getLanguageCode();
  Future<void> setLanguageCode(String code);
  Future<Locale?> getLocale();
  Future<void> setLocale(Locale locale);
  Future<String?> getNickname();
  Future<void> setNickname(String value);
  Future<String?> getStatusMessage();
  Future<void> setStatusMessage(String value);
  Future<String?> getAvatarPath();
  Future<void> setAvatarPath(String? path);
  Future<String?> getCardText();
  Future<void> setCardText(String? text);
  Future<String?> getDraft(String peerId);
  Future<void> setDraft(String peerId, String text);
  Future<Rect?> getWindowBounds();
  Future<void> setWindowBounds(Rect rect);
  Future<bool> getWindowMaximized();
  Future<void> setWindowMaximized(bool value);
  Future<double?> getSplitterPosition();
  Future<void> setSplitterPosition(double value);
  Future<String?> getDownloadsDirectory();
  Future<void> setDownloadsDirectory(String? path);
}

/// Notification and per-account behavior preferences.
abstract class INotificationPrefs {
  Future<bool> getNotificationSoundEnabled([String? toxId]);
  Future<void> setNotificationSoundEnabled(bool value, [String? toxId]);
  Future<bool> getAutoAcceptFriends([String? toxId]);
  Future<void> setAutoAcceptFriends(bool value, [String? toxId]);
  Future<bool> getAutoAcceptGroupInvites([String? toxId]);
  Future<void> setAutoAcceptGroupInvites(bool value, [String? toxId]);
  Future<bool> getAutoLogin([String? toxId]);
  Future<void> setAutoLogin(bool value, [String? toxId]);
}
