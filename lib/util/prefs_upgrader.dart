import 'package:shared_preferences/shared_preferences.dart';

/// Current schema version for global preferences.
/// Bump this when adding migration steps and implement the new step in [_runGlobalMigration].
const int currentGlobalPrefsVersion = 2;

/// Current schema version for per-account preferences.
/// Bump when adding per-account migration steps.
const int currentAccountPrefsVersion = 1;

/// Key used to store the global schema version in SharedPreferences.
const String _kPrefsSchemaVersion = 'prefs_schema_version';

/// Key prefix for per-account schema version.
String _accountPrefsVersionKey(String accountPrefix) =>
    'account_prefs_version_$accountPrefix';

/// Thrown when stored preferences were saved by a newer app version.
/// The app should prompt the user to upgrade and not overwrite data.
class PrefsStorageNewerThanAppException implements Exception {
  final int storedVersion;
  final int currentVersion;

  PrefsStorageNewerThanAppException(this.storedVersion, this.currentVersion);

  @override
  String toString() =>
      'PrefsStorageNewerThanAppException(stored: $storedVersion, current: $currentVersion)';
}

/// Runs schema upgrades for SharedPreferences.
///
/// Handles both global migrations (theme defaults, etc.) and per-account
/// migrations (moving data from unscoped to account-scoped keys).
class PrefsUpgrader {
  PrefsUpgrader._();

  /// Run global schema migrations.
  static Future<void> run(SharedPreferences p) async {
    final stored = p.getInt(_kPrefsSchemaVersion) ?? 0;

    if (stored > currentGlobalPrefsVersion) {
      throw PrefsStorageNewerThanAppException(stored, currentGlobalPrefsVersion);
    }

    if (stored < currentGlobalPrefsVersion) {
      for (int from = stored; from < currentGlobalPrefsVersion; from++) {
        await _runGlobalMigration(from, from + 1, p);
      }
      await p.setInt(_kPrefsSchemaVersion, currentGlobalPrefsVersion);
    }
  }

  /// Run per-account schema migrations for the given account.
  /// Call this when an account is activated (login / switch).
  static Future<void> runAccountMigrations(
    SharedPreferences p,
    String accountPrefix,
  ) async {
    if (accountPrefix.isEmpty) return;

    final versionKey = _accountPrefsVersionKey(accountPrefix);
    final stored = p.getInt(versionKey) ?? 0;

    if (stored >= currentAccountPrefsVersion) return;

    for (int from = stored; from < currentAccountPrefsVersion; from++) {
      await _runAccountMigration(from, from + 1, p, accountPrefix);
    }
    await p.setInt(versionKey, currentAccountPrefsVersion);
  }

  // ---------- Global migrations ----------

  static Future<void> _runGlobalMigration(
      int from, int to, SharedPreferences p) async {
    if (from == 0 && to == 1) {
      // v0→v1: ensure theme_mode has a valid value if missing
      final theme = p.getString('theme_mode');
      if (theme == null || theme.isEmpty) {
        await p.setString('theme_mode', 'light');
      }
      return;
    }
    if (from == 1 && to == 2) {
      // v1→v2: no-op placeholder. Per-account settings migration is now
      // handled lazily via read-time fallback in Prefs (scoped bool keys),
      // so no eager migration is needed at this step.
      return;
    }
  }

  // ---------- Per-account migrations ----------

  static Future<void> _runAccountMigration(
      int from, int to, SharedPreferences p, String accountPrefix) async {
    if (from == 0 && to == 1) {
      // v0→v1: Migrate groups/quitGroups from unscoped to account-scoped keys.
      // This absorbs the logic previously in SharedPreferencesAdapter._migrateIfNeeded().
      final accountGroupsKey = 'groups_list_$accountPrefix';
      final existing = p.getStringList(accountGroupsKey);
      if (existing != null && existing.isNotEmpty) return; // already migrated

      final oldGroups = p.getStringList('groups_list');
      if (oldGroups != null && oldGroups.isNotEmpty) {
        await p.setStringList(accountGroupsKey, oldGroups);
        final oldQuit = p.getStringList('quit_groups_list');
        if (oldQuit != null && oldQuit.isNotEmpty) {
          await p.setStringList('quit_groups_list_$accountPrefix', oldQuit);
        }
        // Note: don't remove old unscoped keys here — other accounts might
        // not have been migrated yet. They'll be cleaned up eventually.
      }
      return;
    }
  }
}
