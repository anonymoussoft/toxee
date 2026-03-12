/// In-memory store for the current account's profile encryption password.
/// Used to re-encrypt tox_profile.tox on logout. Never persisted to disk.
class SessionPasswordStore {
  static String? _toxId;
  static String? _password;

  static void set(String toxId, String password) {
    _toxId = toxId;
    _password = password.isEmpty ? null : password;
  }

  static String? get(String toxId) {
    if (_toxId != toxId) return null;
    return _password;
  }

  static void clear([String? toxId]) {
    if (toxId == null || _toxId == toxId) {
      _toxId = null;
      _password = null;
    }
  }
}
