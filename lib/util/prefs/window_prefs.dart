part of 'package:toxee/util/prefs.dart';

// --- Window/layout state (desktop) ---

Future<Rect?> _getWindowBoundsImpl(SharedPreferences p) async {
  final s = p.getString(Prefs._kWindowBounds);
  if (s == null || s.isEmpty) return null;
  final parts = s.split(',');
  if (parts.length != 4) return null;
  final values = parts.map((e) => double.tryParse(e.trim())).toList();
  if (values.any((v) => v == null)) return null;
  return Rect.fromLTWH(values[0]!, values[1]!, values[2]!, values[3]!);
}

Future<void> _setWindowBoundsImpl(SharedPreferences p, Rect rect) async {
  await p.setString(
    Prefs._kWindowBounds,
    '${rect.left},${rect.top},${rect.width},${rect.height}',
  );
}

Future<bool> _getWindowMaximizedImpl(SharedPreferences p) async {
  return p.getBool(Prefs._kWindowMaximized) ?? false;
}

Future<void> _setWindowMaximizedImpl(SharedPreferences p, bool value) async {
  await p.setBool(Prefs._kWindowMaximized, value);
}
