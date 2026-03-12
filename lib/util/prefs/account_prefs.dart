part of 'package:toxee/util/prefs.dart';

// Account list (implementation helper used by Prefs)

Future<List<Map<String, String>>> _getAccountListImpl(SharedPreferences p) async {
  final accountsJson = p.getString(Prefs._kAccountList);
  if (accountsJson == null || accountsJson.isEmpty) return [];
  try {
    final List<dynamic> decoded = jsonDecode(accountsJson);
    return decoded.map((e) => Map<String, String>.from(e)).toList();
  } catch (_) {
    return [];
  }
}

Future<void> _setAccountListImpl(SharedPreferences p, List<Map<String, String>> accounts) async {
  await p.setString(Prefs._kAccountList, jsonEncode(accounts));
}
