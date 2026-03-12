import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'tox_utils.dart';

part 'prefs/window_prefs.dart';
part 'prefs/security_prefs.dart';
part 'prefs/account_prefs.dart';
part 'prefs/chat_prefs.dart';

class Prefs {
  static const _kServerId = 'server_id';
  static String _draftKey(String peerId) => 'draft_$peerId';
  static const _kPinned = 'pinned_peers';
  static const _kMuted = 'muted_peers';
  static const _kGroups = 'groups_list';
  static const _kQuitGroups = 'quit_groups_list'; // Groups that user has quit
  static const _kNickname = 'self_nickname';
  static const _kStatusMsg = 'self_status_msg';
  static const _kThemeMode = 'theme_mode'; // 'light' | 'dark'
  static const _kAvatarPath = 'self_avatar_path';
  static String _groupNameKey(String gid) => 'group_name_$gid';
  static const _kLocalFriends = 'local_friends';
  static const _kLanguage = 'language_code'; // e.g. 'en', 'zh'
  static const _kCurrentBootstrapHost = 'current_bootstrap_host';
  static const _kCurrentBootstrapPort = 'current_bootstrap_port';
  static const _kCurrentBootstrapPubkey = 'current_bootstrap_pubkey';
  static const _kBootstrapNodeMode = 'bootstrap_node_mode'; // 'manual', 'auto', or 'lan'
  static const _kLanBootstrapPort = 'lan_bootstrap_port'; // Local bootstrap service port
  static const _kLanBootstrapServiceRunning = 'lan_bootstrap_service_running'; // Service running status
  static const _kAutoAcceptFriends = 'auto_accept_friends';
  static const _kAutoAcceptGroupInvites = 'auto_accept_group_invites';
  static const _kAutoLogin = 'auto_login';
  static const _kNotificationSoundEnabled = 'notification_sound_enabled';
  static const _kCardText = 'self_card_text';
  static const _kCurrentAccountToxId = 'current_account_tox_id'; // Which account is active (for per-account avatar/pinned/localFriends)
  static const _kDownloadsDirectory = 'downloads_directory';
  static const _kProfileStorageRoot = 'profile_storage_root'; // Optional custom root for tox profiles (survives uninstall when outside app)
  static const _kAutoDownloadSizeLimit = 'auto_download_size_limit'; // in MB
  static const _kIrcAppInstalled = 'irc_app_installed'; // bool
  static const _kIrcChannels = 'irc_channels'; // List<String> - JSON array of channel names
  static const _kIrcServer = 'irc_server'; // String - IRC server address (default: "irc.libera.chat")
  static const _kIrcPort = 'irc_port'; // int - IRC server port (default: 6667)
  static const _kIrcUseSasl = 'irc_use_sasl'; // bool - Whether to use SASL authentication
  static String _ircChannelPasswordKey(String channel) => 'irc_channel_password_$channel';
  // Window/layout state (desktop)
  static const _kWindowBounds = 'window_bounds'; // "left,top,width,height"
  static const _kWindowMaximized = 'window_maximized';
  static const _kSplitterPosition = 'splitter_position'; // conversation list width or ratio (0.0-1.0)
  // Contact list sorting
  static const _kFriendListSortingMode = 'friend_list_sorting_mode'; // 'name' | 'activity'
  static String _friendActivityKey(String userId) => 'friend_activity_$userId';

  // Password salt key prefix
  static const _kPasswordSaltPrefix = 'account_password_salt_';
  static String _passwordSaltKey(String toxId) => '$_kPasswordSaltPrefix$toxId';

  /// PBKDF2 stored hash prefix (new format); without it we treat as legacy SHA256.
  static const _kPbkdf2Prefix = 'pbkdf2:';
  static const int _pbkdf2Iterations = 150000;
  static const int _pbkdf2Bits = 256;

  // Per-account settings keys (scoped by account prefix, replacing JSON storage)
  static const _kAccountAutoAcceptFriends = 'acct_auto_accept_friends';
  static const _kAccountAutoAcceptGroupInvites = 'acct_auto_accept_group_invites';
  static const _kAccountAutoLogin = 'acct_auto_login';
  static const _kAccountNotificationSound = 'acct_notification_sound';

  // ---- Cached state (set by initialize / setCurrentAccountToxId) ----
  static SharedPreferences? _cachedPrefs;
  static bool _accountToxIdCached = false;
  static String? _cachedCurrentAccountToxId;

  /// Secure storage for IRC channel passwords (platform Keystore/Keychain).
  static FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();

  /// Initialize the Prefs cache. Must be called once at app startup after
  /// SharedPreferences.getInstance() returns (typically in main()).
  /// This avoids redundant getInstance() + reload() on every read.
  static Future<void> initialize(SharedPreferences prefs) async {
    _cachedPrefs = prefs;
    _cachedCurrentAccountToxId = prefs.getString(_kCurrentAccountToxId);
    _accountToxIdCached = true;
  }

  /// Get the cached SharedPreferences instance. Falls back to getInstance()
  /// if initialize() hasn't been called yet (e.g. in tests).
  static Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  static Future<String?> getServerId() async {
    final p = await _getPrefs();
    return p.getString(_kServerId);
    }

  static Future<void> setServerId(String value) async {
    final p = await _getPrefs();
    await p.setString(_kServerId, value);
  }

  static Future<String?> getDraft(String peerId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_draftKey(peerId), current);
    return p.getString(key);
  }

  static Future<void> setDraft(String peerId, String text) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_draftKey(peerId), current);
    if (text.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, text);
    }
  }

  /// Storage key for pinned/conversation list scoped by account (avoids loading other account's data).
  static String _scopedKey(String baseKey, String? toxId) {
    if (toxId == null || toxId.isEmpty) return baseKey;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    return '${baseKey}_$prefix';
  }

  static Future<String?> getCurrentAccountToxId() async {
    // Return cached value if available (updated by setCurrentAccountToxId).
    // The reload()-on-every-read pattern was causing a disk read per call;
    // the cache is invalidated only on explicit account switch.
    // Use _accountToxIdCached sentinel to distinguish "not loaded" from "loaded null".
    if (_accountToxIdCached) {
      return _cachedCurrentAccountToxId;
    }
    final p = await _getPrefs();
    _cachedCurrentAccountToxId = p.getString(_kCurrentAccountToxId);
    _accountToxIdCached = true;
    return _cachedCurrentAccountToxId;
  }

  static Future<void> setCurrentAccountToxId(String? toxId) async {
    final p = await _getPrefs();
    if (toxId == null || toxId.isEmpty) {
      await p.remove(_kCurrentAccountToxId);
      _cachedCurrentAccountToxId = null;
    } else {
      final trimmed = toxId.trim();
      await p.setString(_kCurrentAccountToxId, trimmed);
      _cachedCurrentAccountToxId = trimmed;
    }
    _accountToxIdCached = true;
  }

  static Future<Set<String>> getPinned() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kPinned, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setPinned(Set<String> peers) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kPinned, current);
    await p.setStringList(key, peers.toList());
  }

  static Future<Set<String>> getMuted() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kMuted, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setMuted(Set<String> peers) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kMuted, current);
    await p.setStringList(key, peers.toList());
  }

  static Future<Set<String>> getGroups() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kGroups, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setGroups(Set<String> groups) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kGroups, current);
    await p.setStringList(key, groups.toList());
  }

  static Future<Set<String>> getQuitGroups() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kQuitGroups, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setQuitGroups(Set<String> groups) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kQuitGroups, current);
    await p.setStringList(key, groups.toList());
  }

  static Future<void> addQuitGroup(String groupId) async {
    final quitGroups = await getQuitGroups();
    quitGroups.add(groupId);
    await setQuitGroups(quitGroups);
  }

  static Future<void> removeQuitGroup(String groupId) async {
    final quitGroups = await getQuitGroups();
    quitGroups.remove(groupId);
    await setQuitGroups(quitGroups);
  }

  static Future<String?> getNickname() async {
    final p = await _getPrefs();
    return p.getString(_kNickname);
  }

  static Future<void> setNickname(String value) async {
    final p = await _getPrefs();
    if (value.isEmpty) {
      await p.remove(_kNickname);
    } else {
      await p.setString(_kNickname, value);
    }
  }

  static Future<String?> getStatusMessage() async {
    final p = await _getPrefs();
    return p.getString(_kStatusMsg);
  }

  static Future<void> setStatusMessage(String value) async {
    final p = await _getPrefs();
    if (value.isEmpty) {
      await p.remove(_kStatusMsg);
    } else {
      await p.setString(_kStatusMsg, value);
    }
  }

  static Future<String> getThemeMode() async {
    final p = await _getPrefs();
    return p.getString(_kThemeMode) ?? 'light';
  }

  static Future<void> setThemeMode(String mode) async {
    final p = await _getPrefs();
    await p.setString(_kThemeMode, (mode == 'dark') ? 'dark' : 'light');
  }

  static Future<String?> getAvatarPath() async {
    final current = await getCurrentAccountToxId();
    if (current != null && current.isNotEmpty) {
      final account = await getAccountByToxId(current);
      final path = account?['avatarPath'];
      if (path != null && path.isNotEmpty) return path;
    }
    final p = await _getPrefs();
    return p.getString(_kAvatarPath);
  }

  static Future<void> setAvatarPath(String? path) async {
    final current = await getCurrentAccountToxId();
    if (current != null && current.isNotEmpty) {
      await setAccountAvatarPath(current, path);
    }
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kAvatarPath);
    } else {
      await p.setString(_kAvatarPath, path);
    }
  }

  static Future<String?> getGroupName(String groupId) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return null;
    final p = await _getPrefs();
    final key = _scopedKey(_groupNameKey(groupId), current);
    return p.getString(key);
  }

  static Future<void> setGroupName(String groupId, String name) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_groupNameKey(groupId), current);
    if (name.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, name);
    }
  }

  static Future<Set<String>> getLocalFriends() async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    return _getLocalFriendsImpl(p, current, _scopedKey);
  }

  static Future<void> setLocalFriends(Set<String> ids) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    return _setLocalFriendsImpl(p, current, ids, _scopedKey);
  }

  static Future<String?> getLanguageCode() async {
    final p = await _getPrefs();
    return p.getString(_kLanguage);
  }

  static Future<void> setLanguageCode(String code) async {
    final p = await _getPrefs();
    await p.setString(_kLanguage, code);
  }

  // Get Locale from preferences (supports scriptCode). Returns null when no language was ever set (follow system).
  static Future<Locale?> getLocale() async {
    final code = await getLanguageCode();
    if (code == null || code.isEmpty) return null;
    return _stringToLocale(code);
  }

  // Save Locale to preferences (supports scriptCode)
  static Future<void> setLocale(Locale locale) async {
    final code = _localeToString(locale);
    await setLanguageCode(code);
  }

  // Helper method to serialize Locale to string
  static String _localeToString(Locale locale) {
    if (locale.scriptCode != null) {
      return '${locale.languageCode}_${locale.scriptCode}';
    }
    return locale.languageCode;
  }

  // Helper method to deserialize string to Locale
  static Locale _stringToLocale(String code) {
    final parts = code.split('_');
    if (parts.length == 2) {
      return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
    }
    return Locale(parts[0]);
  }

  static Future<({String host, int port, String pubkey})?> getCurrentBootstrapNode() async {
    final p = await _getPrefs();
    final host = p.getString(_kCurrentBootstrapHost);
    final port = p.getInt(_kCurrentBootstrapPort);
    final pubkey = p.getString(_kCurrentBootstrapPubkey);
    if (host != null && port != null && pubkey != null) {
      return (host: host, port: port, pubkey: pubkey);
    }
    return null;
  }

  static Future<void> setCurrentBootstrapNode(String host, int port, String pubkey) async {
    final p = await _getPrefs();
    await p.setString(_kCurrentBootstrapHost, host);
    await p.setInt(_kCurrentBootstrapPort, port);
    await p.setString(_kCurrentBootstrapPubkey, pubkey);
  }

  static Future<void> clearCurrentBootstrapNode() async {
    final p = await _getPrefs();
    await p.remove(_kCurrentBootstrapHost);
    await p.remove(_kCurrentBootstrapPort);
    await p.remove(_kCurrentBootstrapPubkey);
  }

  /// Get bootstrap node mode: 'manual', 'auto', or 'lan'
  /// Defaults to 'auto' if not set
  static Future<String> getBootstrapNodeMode() async {
    final p = await _getPrefs();
    return p.getString(_kBootstrapNodeMode) ?? 'auto';
  }

  /// Set bootstrap node mode: 'manual', 'auto', or 'lan'
  static Future<void> setBootstrapNodeMode(String mode) async {
    final p = await _getPrefs();
    if (mode == 'manual' || mode == 'auto' || mode == 'lan') {
      await p.setString(_kBootstrapNodeMode, mode);
    }
  }

  /// Get LAN bootstrap service port
  /// Defaults to 33445 if not set
  static Future<int> getLanBootstrapPort() async {
    final p = await _getPrefs();
    return p.getInt(_kLanBootstrapPort) ?? 33445;
  }

  /// Set LAN bootstrap service port
  static Future<void> setLanBootstrapPort(int port) async {
    final p = await _getPrefs();
    await p.setInt(_kLanBootstrapPort, port);
  }

  /// Get LAN bootstrap service running status
  static Future<bool> getLanBootstrapServiceRunning() async {
    final p = await _getPrefs();
    return p.getBool(_kLanBootstrapServiceRunning) ?? false;
  }

  /// Set LAN bootstrap service running status
  static Future<void> setLanBootstrapServiceRunning(bool running) async {
    final p = await _getPrefs();
    await p.setBool(_kLanBootstrapServiceRunning, running);
  }

  /// Get auto-accept friends setting for a specific account.
  /// Priority: scoped key > account_list JSON fallback > global fallback.
  static Future<bool> getAutoAcceptFriends([String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptFriends, toxId);
      final val = p.getBool(key);
      if (val != null) return val;
      // Fallback: check account_list JSON (pre-migration data)
      final account = await getAccountByToxId(toxId);
      if (account != null && account.containsKey('autoAcceptFriends')) {
        final result = account['autoAcceptFriends'] == 'true';
        // Migrate to scoped key
        await p.setBool(key, result);
        return result;
      }
    }
    return p.getBool(_kAutoAcceptFriends) ?? false;
  }

  /// Set auto-accept friends setting for a specific account.
  static Future<void> setAutoAcceptFriends(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptFriends, toxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoAcceptFriends, value);
  }

  /// Get auto-accept group invites setting for a specific account.
  static Future<bool> getAutoAcceptGroupInvites([String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptGroupInvites, toxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(toxId);
      if (account != null && account.containsKey('autoAcceptGroupInvites')) {
        final result = account['autoAcceptGroupInvites'] == 'true';
        await p.setBool(key, result);
        return result;
      }
    }
    return p.getBool(_kAutoAcceptGroupInvites) ?? false;
  }

  /// Set auto-accept group invites setting for a specific account.
  static Future<void> setAutoAcceptGroupInvites(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptGroupInvites, toxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoAcceptGroupInvites, value);
  }

  /// Get auto-login setting for a specific account.
  static Future<bool> getAutoLogin([String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoLogin, toxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(toxId);
      if (account != null && account.containsKey('autoLogin')) {
        final result = account['autoLogin'] == 'true';
        await p.setBool(key, result);
        return result;
      }
      return true; // Default for new accounts
    }
    return p.getBool(_kAutoLogin) ?? true;
  }

  /// Set auto-login setting for a specific account.
  static Future<void> setAutoLogin(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoLogin, toxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoLogin, value);
  }

  /// Get notification sound enabled setting for a specific account.
  static Future<bool> getNotificationSoundEnabled([String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountNotificationSound, toxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(toxId);
      if (account != null && account.containsKey('notificationSoundEnabled')) {
        final result = account['notificationSoundEnabled'] == 'true';
        await p.setBool(key, result);
        return result;
      }
      return true; // Default
    }
    return p.getBool(_kNotificationSoundEnabled) ?? true;
  }

  /// Set notification sound enabled setting for a specific account.
  static Future<void> setNotificationSoundEnabled(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    if (toxId != null && toxId.isNotEmpty) {
      final key = _scopedKey(_kAccountNotificationSound, toxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kNotificationSoundEnabled, value);
  }

  static Future<String?> getCardText() async {
    final p = await _getPrefs();
    return p.getString(_kCardText);
  }

  static Future<void> setCardText(String? value) async {
    final p = await _getPrefs();
    if (value == null || value.isEmpty) {
      await p.remove(_kCardText);
    } else {
      await p.setString(_kCardText, value);
    }
  }

  static Future<String?> getDownloadsDirectory() async {
    final p = await _getPrefs();
    return p.getString(_kDownloadsDirectory);
  }

  static Future<void> setDownloadsDirectory(String? path) async {
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kDownloadsDirectory);
    } else {
      await p.setString(_kDownloadsDirectory, path);
    }
  }

  static Future<String?> getProfileStorageRoot() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kProfileStorageRoot);
  }

  static Future<void> setProfileStorageRoot(String? path) async {
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kProfileStorageRoot);
    } else {
      await p.setString(_kProfileStorageRoot, path);
    }
  }

  static Future<int> getAutoDownloadSizeLimit() async {
    final p = await _getPrefs();
    // Default to 30MB if not set
    return p.getInt(_kAutoDownloadSizeLimit) ?? 30;
  }

  static Future<void> setAutoDownloadSizeLimit(int sizeInMB) async {
    final p = await _getPrefs();
    await p.setInt(_kAutoDownloadSizeLimit, sizeInMB);
  }

  // Avatar hash tracking
  static String _avatarHashKey(String friendId) => 'avatar_hash_$friendId';
  static const _selfAvatarHashKey = 'self_avatar_hash';

  static Future<String?> getFriendAvatarHash(String friendId) async {
    final p = await _getPrefs();
    return p.getString(_avatarHashKey(friendId));
  }

  static Future<void> setFriendAvatarHash(String friendId, String hash) async {
    final p = await _getPrefs();
    await p.setString(_avatarHashKey(friendId), hash);
  }

  static Future<String?> getSelfAvatarHash() async {
    final p = await _getPrefs();
    return p.getString(_selfAvatarHashKey);
  }

  static Future<void> setSelfAvatarHash(String? hash) async {
    final p = await _getPrefs();
    if (hash == null || hash.isEmpty) {
      await p.remove(_selfAvatarHashKey);
    } else {
      await p.setString(_selfAvatarHashKey, hash);
    }
  }

  // Friend avatar path storage
  /// Key uses normalized (64-char) friendId so 64-char and 76-char callers share the same entry.
  static String _friendAvatarPathKey(String friendId) =>
      'friend_avatar_path_${normalizeToxId(friendId)}';

  static Future<String?> getFriendAvatarPath(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendAvatarPathKey(friendId), current);
    final value = p.getString(key);
    if (value != null) return value;
    // Fallback 1: avatar may have been saved with raw 76-char id from native
    if (friendId.length > 64) {
      final legacyKey = _scopedKey('friend_avatar_path_$friendId', current);
      final legacy = p.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        unawaited(setFriendAvatarPath(friendId, legacy));
        return legacy;
      }
    }
    // Fallback 2: avatar stored by service layer without account scoping
    final rawKey = _friendAvatarPathKey(friendId);
    if (rawKey != key) {
      final raw = p.getString(rawKey);
      if (raw != null && raw.isNotEmpty) {
        unawaited(setFriendAvatarPath(friendId, raw));
        return raw;
      }
    }
    return null;
  }

  static Future<void> setFriendAvatarPath(String friendId, String? path) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendAvatarPathKey(friendId), current);
    if (path == null || path.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, path);
    }
  }

  // Friend nickname storage (from Tox, different from remark which is user-edited)
  static String _friendNicknameKey(String friendId) => 'friend_nickname_$friendId';

  static Future<String?> getFriendNickname(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendNicknameKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendNickname(String friendId, String nickname) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendNicknameKey(friendId), current);
    if (nickname.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, nickname);
    }
  }

  // Friend status message storage (from Tox, selfSignature)
  static String _friendStatusMessageKey(String friendId) => 'friend_status_message_$friendId';

  static Future<String?> getFriendStatusMessage(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendStatusMessageKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendStatusMessage(String friendId, String statusMessage) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendStatusMessageKey(friendId), current);
    if (statusMessage.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, statusMessage);
    }
  }

  // Friend remark storage (user-edited, different from nickname)
  static String _friendRemarkKey(String friendId) => 'friend_remark_$friendId';

  static Future<String?> getFriendRemark(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendRemarkKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendRemark(String friendId, String remark) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendRemarkKey(friendId), current);
    if (remark.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, remark);
    }
  }

  // Do not disturb storage
  static String _doNotDisturbKey(String friendId) => 'do_not_disturb_$friendId';

  static Future<bool> getDoNotDisturb(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_doNotDisturbKey(friendId), current);
    return p.getBool(key) ?? false;
  }

  static Future<void> setDoNotDisturb(String friendId, bool value) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_doNotDisturbKey(friendId), current);
    await p.setBool(key, value);
  }

  // Blacklist storage (user-specific, bound to current user Tox ID)
  static String _blackListKey(String? userToxId) {
    // Use Tox ID if provided, otherwise use 'default' (should not happen in normal flow)
    final toxId = userToxId ?? 'default';
    return 'black_list_$toxId';
  }

  static Future<Set<String>> getBlackList([String? userToxId]) async {
    final p = await _getPrefs();
    final key = _blackListKey(userToxId);
    final list = p.getStringList(key) ?? const <String>[];
    return list.toSet();
  }

  static Future<void> setBlackList(Set<String> userIDs, [String? userToxId]) async {
    final p = await _getPrefs();
    final key = _blackListKey(userToxId);
    await p.setStringList(key, userIDs.toList());
  }

  static Future<void> addToBlackList(List<String> userIDs, [String? userToxId]) async {
    final blackList = await getBlackList(userToxId);
    blackList.addAll(userIDs);
    await setBlackList(blackList, userToxId);
  }

  static Future<void> removeFromBlackList(List<String> userIDs, [String? userToxId]) async {
    final blackList = await getBlackList(userToxId);
    blackList.removeAll(userIDs);
    await setBlackList(blackList, userToxId);
  }

  // Group member name card storage
  static String _groupMemberNameCardKey(String groupId, String userId) => 'group_member_namecard_${groupId}_$userId';

  static Future<String?> getGroupMemberNameCard(String groupId, String userId) async {
    final p = await _getPrefs();
    return p.getString(_groupMemberNameCardKey(groupId, userId));
  }

  static Future<void> setGroupMemberNameCard(String groupId, String userId, String nameCard) async {
    final p = await _getPrefs();
    if (nameCard.isEmpty) {
      await p.remove(_groupMemberNameCardKey(groupId, userId));
    } else {
      await p.setString(_groupMemberNameCardKey(groupId, userId), nameCard);
    }
  }

  // Group owner storage
  static String _groupOwnerKey(String groupId) => 'group_owner_$groupId';

  static Future<String?> getGroupOwner(String groupId) async {
    final p = await _getPrefs();
    return p.getString(_groupOwnerKey(groupId));
  }

  static Future<void> setGroupOwner(String groupId, String userId) async {
    final p = await _getPrefs();
    await p.setString(_groupOwnerKey(groupId), userId);
  }

  // Group avatar (faceUrl) storage
  static String _groupAvatarKey(String groupId) => 'group_avatar_$groupId';

  static Future<String?> getGroupAvatar(String groupId) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return null;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAvatarKey(groupId), current);
    return p.getString(key);
  }

  static Future<void> setGroupAvatar(String groupId, String? faceUrl) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAvatarKey(groupId), current);
    if (faceUrl == null || faceUrl.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, faceUrl);
    }
  }

  /// Clear per-account data from SharedPreferences for the given account.
  /// Does NOT remove global settings (bootstrap nodes, theme, language, IRC, etc.).
  /// Also cleans up scoped keys and password hash for the account.
  static Future<void> clearAccountData(String toxId) async {
    final p = await _getPrefs();

    // Fixed keys to remove (legacy single-account keys)
    final fixedKeys = <String>[
      _kPinned, _kMuted, _kGroups, _kQuitGroups,
      _kNickname, _kStatusMsg, _kAvatarPath, _kLocalFriends,
      _kCurrentAccountToxId, _kCardText, _kAutoAcceptFriends,
      _kAutoAcceptGroupInvites, _kNotificationSoundEnabled,
      _selfAvatarHashKey, _kAutoLogin,
    ];

    // Dynamic key prefixes to match
    const dynamicPrefixes = <String>[
      'black_list_',
      'draft_',
      'group_name_',
      'avatar_hash_',
      'friend_avatar_path_',
      'friend_nickname_',
      'friend_remark_',
      'friend_status_message_',
      'friend_activity_',
      'do_not_disturb_',
      'group_member_namecard_',
      'group_owner_',
      'group_avatar_',
      'irc_channel_password_',
      'acct_auto_accept_friends_',
      'acct_auto_accept_group_invites_',
      'acct_auto_login_',
      'acct_notification_sound_',
      'account_password_salt_',
    ];

    // Collect all keys to remove in one pass
    final keysToRemove = <String>{...fixedKeys};
    final allKeys = p.getKeys();
    for (final key in allKeys) {
      for (final prefix in dynamicPrefixes) {
        if (key.startsWith(prefix)) {
          keysToRemove.add(key);
          break; // matched, skip remaining prefixes
        }
      }
    }

    // Remove all collected keys (Future.wait for parallelism)
    await Future.wait(keysToRemove.map((key) => p.remove(key)));

    // Clean up scoped keys and password hash for this account
    if (toxId.isNotEmpty) {
      await clearScopedKeysForAccount(toxId);
      await removeAccountPassword(toxId);
    }

    // Invalidate cache since current account was cleared
    _cachedCurrentAccountToxId = null;
    _accountToxIdCached = false;
  }

  /// Remove all SharedPreferences keys scoped to the given account.
  /// Call this when deleting an account so that account's data does not remain.
  static Future<void> clearScopedKeysForAccount(String toxId) async {
    if (toxId.isEmpty) return;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final suffix = '_$prefix';
    final p = await _getPrefs();
    final keysToRemove = p.getKeys().where((key) => key.endsWith(suffix)).toList();
    await Future.wait(keysToRemove.map((key) => p.remove(key)));
  }

  /// Export all scoped preferences for an account as a serializable map.
  /// Used for full backup (.zip) export.
  static Future<Map<String, dynamic>> exportScopedPrefsForAccount(String toxId) async {
    if (toxId.isEmpty) return {};
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final suffix = '_$prefix';
    final p = await _getPrefs();
    final result = <String, dynamic>{};
    for (final key in p.getKeys()) {
      if (key.endsWith(suffix)) {
        // Strip suffix to get base key name for portability
        final baseKey = key.substring(0, key.length - suffix.length);
        final value = p.get(key);
        if (value != null) {
          result[baseKey] = value;
        }
      }
    }
    return result;
  }

  /// Import scoped preferences for an account from a map.
  /// Used for full backup (.zip) import/restore.
  static Future<void> importScopedPrefsForAccount(String toxId, Map<String, dynamic> data) async {
    if (toxId.isEmpty) return;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final p = await _getPrefs();
    for (final entry in data.entries) {
      final scopedKey = '${entry.key}_$prefix';
      final value = entry.value;
      if (value is String) {
        await p.setString(scopedKey, value);
      } else if (value is int) {
        await p.setInt(scopedKey, value);
      } else if (value is double) {
        await p.setDouble(scopedKey, value);
      } else if (value is bool) {
        await p.setBool(scopedKey, value);
      } else if (value is List) {
        await p.setStringList(scopedKey, value.cast<String>());
      }
    }
  }

  // IRC App management
  static Future<bool> getIrcAppInstalled() async {
    final p = await _getPrefs();
    return _getIrcAppInstalledImpl(p);
  }

  static Future<void> setIrcAppInstalled(bool installed) async {
    final p = await _getPrefs();
    return _setIrcAppInstalledImpl(p, installed);
  }

  static Future<List<String>> getIrcChannels() async {
    final p = await _getPrefs();
    return _getIrcChannelsImpl(p);
  }

  static Future<void> setIrcChannels(List<String> channels) async {
    final p = await _getPrefs();
    return _setIrcChannelsImpl(p, channels);
  }

  static Future<void> addIrcChannel(String channel) async {
    final channels = await getIrcChannels();
    if (!channels.contains(channel)) {
      channels.add(channel);
      await setIrcChannels(channels);
    }
  }

  static Future<void> removeIrcChannel(String channel) async {
    final channels = await getIrcChannels();
    channels.remove(channel);
    await setIrcChannels(channels);
    // Remove password when channel is removed
    await removeIrcChannelPassword(channel);
  }

  static Future<String?> getIrcChannelPassword(String channel) async {
    final key = _ircChannelPasswordKey(channel);
    // Prefer secure storage
    final fromSecure = await _secureStorage.read(key: key);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Migrate from legacy SharedPreferences
    final p = await _getPrefs();
    final legacy = p.getString(key);
    if (legacy != null) {
      await _secureStorage.write(key: key, value: legacy);
      await p.remove(key);
      return legacy;
    }
    return null;
  }

  static Future<void> setIrcChannelPassword(String channel, String? password) async {
    final key = _ircChannelPasswordKey(channel);
    if (password == null || password.isEmpty) {
      await _secureStorage.delete(key: key);
      final p = await _getPrefs();
      await p.remove(key);
    } else {
      await _secureStorage.write(key: key, value: password);
      final p = await _getPrefs();
      await p.remove(key);
    }
  }

  static Future<void> removeIrcChannelPassword(String channel) async {
    final key = _ircChannelPasswordKey(channel);
    await _secureStorage.delete(key: key);
    final p = await _getPrefs();
    await p.remove(key);
  }

  // IRC Server Configuration
  static Future<String> getIrcServer() async {
    final p = await _getPrefs();
    return _getIrcServerImpl(p);
  }

  static Future<void> setIrcServer(String server) async {
    final p = await _getPrefs();
    return _setIrcServerImpl(p, server);
  }

  static Future<int> getIrcPort() async {
    final p = await _getPrefs();
    return _getIrcPortImpl(p);
  }

  static Future<void> setIrcPort(int port) async {
    final p = await _getPrefs();
    return _setIrcPortImpl(p, port);
  }

  static Future<bool> getIrcUseSasl() async {
    final p = await _getPrefs();
    return _getIrcUseSaslImpl(p);
  }

  static Future<void> setIrcUseSasl(bool useSasl) async {
    final p = await _getPrefs();
    return _setIrcUseSaslImpl(p, useSasl);
  }

  // Account list management for multiple accounts
  static const _kAccountList = 'account_list'; // JSON array of account info
  static String _accountPasswordKey(String toxId) => 'account_password_$toxId';

  /// Account info structure: {toxId (required), nickname, statusMessage, lastLoginTime?, avatarPath?, autoLogin?, ...}
  /// toxId is the primary key for account identification
  static Future<List<Map<String, String>>> getAccountList() async {
    final p = await _getPrefs();
    return _getAccountListImpl(p);
  }

  static Future<void> setAccountList(List<Map<String, String>> accounts) async {
    final p = await _getPrefs();
    return _setAccountListImpl(p, accounts);
  }

  /// Add or update an account in the list
  /// toxId is required and used as the primary key
  /// If account with same toxId exists, it will be updated (including nickname)
  static Future<void> addAccount({
    required String toxId,
    String? nickname,
    String? statusMessage,
    String? avatarPath,
    bool? autoLogin,
    bool? autoAcceptFriends,
    bool? autoAcceptGroupInvites,
    bool? notificationSoundEnabled,
  }) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    final accounts = await getAccountList();
    // Find existing account by Tox ID (primary key)
    final existingIndex = accounts.indexWhere((acc) => acc['toxId'] == toxId);
    Map<String, String> account;
    
    if (existingIndex >= 0) {
      // Update existing account
      account = accounts[existingIndex];
      account['lastLoginTime'] = DateTime.now().toIso8601String();
      // Update nickname if provided (allows nickname changes)
      if (nickname != null && nickname.isNotEmpty) {
        account['nickname'] = nickname;
      }
      if (statusMessage != null) {
        account['statusMessage'] = statusMessage;
      }
      if (avatarPath != null) {
        account['avatarPath'] = avatarPath;
      }
      if (autoLogin != null) {
        account['autoLogin'] = autoLogin.toString();
      }
      if (autoAcceptFriends != null) {
        account['autoAcceptFriends'] = autoAcceptFriends.toString();
      }
      if (autoAcceptGroupInvites != null) {
        account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
      }
      if (notificationSoundEnabled != null) {
        account['notificationSoundEnabled'] = notificationSoundEnabled.toString();
      }
      accounts[existingIndex] = account;
    } else {
      // Add new account
      account = <String, String>{
        'toxId': toxId,
        'nickname': nickname ?? '',
        'statusMessage': statusMessage ?? '',
        'lastLoginTime': DateTime.now().toIso8601String(),
      };
      if (avatarPath != null && avatarPath.isNotEmpty) {
        account['avatarPath'] = avatarPath;
      }
      if (autoLogin != null) {
        account['autoLogin'] = autoLogin.toString();
      } else {
        account['autoLogin'] = 'true'; // Default to true
      }
      if (autoAcceptFriends != null) {
        account['autoAcceptFriends'] = autoAcceptFriends.toString();
      } else {
        account['autoAcceptFriends'] = 'false'; // Default to false
      }
      if (autoAcceptGroupInvites != null) {
        account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
      } else {
        account['autoAcceptGroupInvites'] = 'false'; // Default to false
      }
      if (notificationSoundEnabled != null) {
        account['notificationSoundEnabled'] = notificationSoundEnabled.toString();
      } else {
        account['notificationSoundEnabled'] = 'true'; // Default to true
      }
      accounts.add(account);
    }
    await setAccountList(accounts);
  }

  /// Remove an account from the list by Tox ID
  static Future<void> removeAccount(String toxId) async {
    final accounts = await getAccountList();
    accounts.removeWhere((acc) => acc['toxId'] == toxId);
    await setAccountList(accounts);
  }

  /// Update only the avatar path for an existing account (by toxId).
  /// No-op if account not found.
  static Future<void> setAccountAvatarPath(String toxId, String? path) async {
    if (toxId.isEmpty) return;
    final accounts = await getAccountList();
    final index = accounts.indexWhere((acc) => acc['toxId'] == toxId);
    if (index < 0) return;
    if (path == null || path.isEmpty) {
      accounts[index].remove('avatarPath');
    } else {
      accounts[index]['avatarPath'] = path;
    }
    await setAccountList(accounts);
  }

  /// Get account info by Tox ID (primary key)
  /// Normalizes toxId by trimming whitespace for matching
  static Future<Map<String, String>?> getAccountByToxId(String toxId) async {
    final normalizedToxId = toxId.trim();
    final accounts = await getAccountList();
    try {
      // Try exact match first
      return accounts.firstWhere((acc) {
        final accToxId = acc['toxId']?.trim() ?? '';
        return accToxId == normalizedToxId;
      });
    } catch (e) {
      // Try case-insensitive match
      try {
        return accounts.firstWhere((acc) {
          final accToxId = acc['toxId']?.trim() ?? '';
          return accToxId.toLowerCase() == normalizedToxId.toLowerCase();
        });
      } catch (e2) {
        // Try partial match (first 64 chars for long toxIds)
        if (normalizedToxId.length >= 64) {
          try {
            return accounts.firstWhere((acc) {
              final accToxId = acc['toxId']?.trim() ?? '';
              if (accToxId.length >= 64) {
                return accToxId.substring(0, 64) == normalizedToxId.substring(0, 64);
              }
              return false;
            });
          } catch (e3) {
            return null;
          }
        }
        return null;
      }
    }
  }

  /// Get account info by nickname (for backward compatibility and login flow)
  /// Note: This may return null if nickname is not unique
  static Future<Map<String, String>?> getAccountByNickname(String nickname) async {
    final accounts = await getAccountList();
    try {
      return accounts.firstWhere((acc) => acc['nickname'] == nickname);
    } catch (e) {
      return null;
    }
  }

  // Account password management
  /// Check if an account has a password set
  static Future<bool> hasAccountPassword(String toxId) async {
    if (toxId.isEmpty) return false;
    final p = await _getPrefs();
    return p.containsKey(_accountPasswordKey(toxId));
  }

  /// Get account password hash (for verification)
  /// Returns null if no password is set
  static Future<String?> getAccountPasswordHash(String toxId) async {
    if (toxId.isEmpty) return null;
    final p = await _getPrefs();
    return p.getString(_accountPasswordKey(toxId));
  }

  /// Set account password (stores salt + PBKDF2 hash).
  /// New accounts use PBKDF2; legacy SHA256 hashes are migrated on next successful verify.
  static Future<void> setAccountPassword(String toxId, String password) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    if (password.isEmpty) {
      await removeAccountPassword(toxId);
      return;
    }
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _pbkdf2Bits,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final hashBytes = await secretKey.extractBytes();
    final storedHash = '$_kPbkdf2Prefix${base64Encode(hashBytes)}';
    final storedSalt = base64Encode(salt);

    final p = await _getPrefs();
    await p.setString(_accountPasswordKey(toxId), storedHash);
    await p.setString(_passwordSaltKey(toxId), storedSalt);
  }

  /// Remove account password and its salt.
  static Future<void> removeAccountPassword(String toxId) async {
    if (toxId.isEmpty) return;
    final p = await _getPrefs();
    await Future.wait([
      p.remove(_accountPasswordKey(toxId)),
      p.remove(_passwordSaltKey(toxId)),
    ]);
  }

  /// Verify account password.
  /// Supports PBKDF2 (new) and SHA256 salted/unsalted (legacy); migrates legacy on success.
  static Future<bool> verifyAccountPassword(String toxId, String password) async {
    if (toxId.isEmpty || password.isEmpty) return false;

    final storedHash = await getAccountPasswordHash(toxId);
    if (storedHash == null) return false;

    if (storedHash.startsWith(_kPbkdf2Prefix)) {
      final p = await _getPrefs();
      final saltBase64 = p.getString(_passwordSaltKey(toxId));
      if (saltBase64 == null) return false;
      List<int> salt;
      try {
        salt = base64Decode(saltBase64);
      } catch (_) {
        return false;
      }
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _pbkdf2Iterations,
        bits: _pbkdf2Bits,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final hashBytes = await secretKey.extractBytes();
      final expected = base64Encode(hashBytes);
      final actual = storedHash.substring(_kPbkdf2Prefix.length);
      return actual == expected;
    }

    // Legacy SHA256 (salted or unsalted)
    final p = await _getPrefs();
    final salt = p.getString(_passwordSaltKey(toxId));
    if (salt != null && salt.isNotEmpty) {
      final bytes = utf8.encode('$salt$password');
      final hash = crypto.sha256.convert(bytes);
      if (storedHash == hash.toString()) {
        await setAccountPassword(toxId, password);
        return true;
      }
      return false;
    }
    final bytes = utf8.encode(password);
    final hash = crypto.sha256.convert(bytes);
    if (storedHash == hash.toString()) {
      await setAccountPassword(toxId, password);
      return true;
    }
    return false;
  }

  // --- Window/layout state (desktop) ---

  /// Saved window bounds (left, top, width, height). Null if not set or invalid.
  static Future<Rect?> getWindowBounds() async {
    final p = await _getPrefs();
    return _getWindowBoundsImpl(p);
  }

  static Future<void> setWindowBounds(Rect rect) async {
    final p = await _getPrefs();
    return _setWindowBoundsImpl(p, rect);
  }

  static Future<bool> getWindowMaximized() async {
    final p = await _getPrefs();
    return _getWindowMaximizedImpl(p);
  }

  static Future<void> setWindowMaximized(bool value) async {
    final p = await _getPrefs();
    return _setWindowMaximizedImpl(p, value);
  }

  /// Saved splitter position (e.g. conversation list width in logical pixels, or ratio 0.0–1.0). Null if not set.
  static Future<double?> getSplitterPosition() async {
    final p = await _getPrefs();
    final v = p.getDouble(_kSplitterPosition);
    return v;
  }

  static Future<void> setSplitterPosition(double value) async {
    final p = await _getPrefs();
    await p.setDouble(_kSplitterPosition, value);
  }

  // --- Friend list sorting (name vs activity) ---

  /// 'name' or 'activity'. Default 'name'.
  static Future<String> getFriendListSortingMode() async {
    final p = await _getPrefs();
    final v = p.getString(_kFriendListSortingMode) ?? 'name';
    return (v == 'activity' || v == 'name') ? v : 'name';
  }

  static Future<void> setFriendListSortingMode(String mode) async {
    final p = await _getPrefs();
    await p.setString(_kFriendListSortingMode, mode == 'activity' ? 'activity' : 'name');
  }

  /// Last activity time (milliseconds since epoch) for a friend. Used for "sort by activity".
  static Future<DateTime?> getFriendActivity(String userId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendActivityKey(userId), current);
    final ms = p.getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setFriendActivity(String userId, DateTime time) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendActivityKey(userId), current);
    await p.setInt(key, time.millisecondsSinceEpoch);
  }
}


