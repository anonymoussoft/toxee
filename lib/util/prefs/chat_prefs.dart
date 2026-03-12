part of 'package:toxee/util/prefs.dart';

// Chat/conversation prefs (implementation helper used by Prefs)

Future<Set<String>> _getLocalFriendsImpl(
  SharedPreferences p,
  String? currentAccountToxId,
  String Function(String, String?) scopedKey,
) async {
  if (currentAccountToxId == null || currentAccountToxId.isEmpty) return <String>{};
  final key = scopedKey(Prefs._kLocalFriends, currentAccountToxId);
  final list = p.getStringList(key) ?? const <String>[];
  return list.toSet();
}

Future<void> _setLocalFriendsImpl(
  SharedPreferences p,
  String? currentAccountToxId,
  Set<String> ids,
  String Function(String, String?) scopedKey,
) async {
  if (currentAccountToxId == null || currentAccountToxId.isEmpty) return;
  final key = scopedKey(Prefs._kLocalFriends, currentAccountToxId);
  final success = await p.setStringList(key, ids.toList());
  if (!success) {
    throw Exception('Failed to save local friends to SharedPreferences');
  }
}
