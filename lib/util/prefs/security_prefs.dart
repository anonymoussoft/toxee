part of 'package:toxee/util/prefs.dart';

// IRC Server Configuration (implementation helpers used by Prefs)

Future<String> _getIrcServerImpl(SharedPreferences p) async {
  return p.getString(Prefs._kIrcServer) ?? 'irc.libera.chat';
}

Future<void> _setIrcServerImpl(SharedPreferences p, String server) async {
  await p.setString(Prefs._kIrcServer, server);
}

Future<int> _getIrcPortImpl(SharedPreferences p) async {
  return p.getInt(Prefs._kIrcPort) ?? 6667;
}

Future<void> _setIrcPortImpl(SharedPreferences p, int port) async {
  await p.setInt(Prefs._kIrcPort, port);
}

Future<bool> _getIrcUseSaslImpl(SharedPreferences p) async {
  return p.getBool(Prefs._kIrcUseSasl) ?? false;
}

Future<void> _setIrcUseSaslImpl(SharedPreferences p, bool useSasl) async {
  await p.setBool(Prefs._kIrcUseSasl, useSasl);
}

Future<bool> _getIrcAppInstalledImpl(SharedPreferences p) async {
  return p.getBool(Prefs._kIrcAppInstalled) ?? false;
}

Future<void> _setIrcAppInstalledImpl(SharedPreferences p, bool installed) async {
  await p.setBool(Prefs._kIrcAppInstalled, installed);
}

Future<List<String>> _getIrcChannelsImpl(SharedPreferences p) async {
  final channelsJson = p.getString(Prefs._kIrcChannels);
  if (channelsJson == null || channelsJson.isEmpty) return [];
  try {
    final List<dynamic> decoded = jsonDecode(channelsJson);
    return decoded.cast<String>();
  } catch (_) {
    return [];
  }
}

Future<void> _setIrcChannelsImpl(SharedPreferences p, List<String> channels) async {
  await p.setString(Prefs._kIrcChannels, jsonEncode(channels));
}
