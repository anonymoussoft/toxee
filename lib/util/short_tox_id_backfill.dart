import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'logger.dart';
import 'prefs.dart';

/// One-shot backfill that upgrades persisted 64-char Tox IDs to the full
/// 76-char Tox address (`public_key || nospam || checksum`) once the live
/// [FfiChatService] has resolved its identity.
///
/// Background (F12): the account-import path
/// (`AccountExportService.importAccountData` -> Tim2Tox
/// `tim2tox_ffi_extract_tox_id_from_profile`) returns only the **64-char
/// public key** because the underlying C helper calls
/// `tox_self_get_public_key()` on a temporary Tox instance. Imported account
/// records therefore land in `account_list` / `current_account_tox_id`
/// missing the 12-char `nospam + checksum` suffix the Tox protocol requires
/// for a complete, shareable address. A peer adding such an account back can
/// observe the truncation and can't validate nospam/checksum on what gets
/// shared in QR/clipboard/profile UIs.
///
/// At runtime, once that account is actually logged in, Tim2Tox has the full
/// address available via [FfiChatService.getSelfToxId]. This helper runs
/// post-login (from [AccountService.initializeServiceForAccount]) and, when
/// the persisted ID is shorter than the FFI-resolved one and the long ID is
/// a prefix-extension of the short one, rewrites the durable records:
///
/// * `account_list` entry's `toxId` field
/// * `current_account_tox_id` pointer (when it pointed at the short form)
/// * Per-account password keys (secure-storage + legacy prefs) via
///   [Prefs.migrateAccountPasswordKeys] — these are keyed by the full toxId
///   string and would otherwise become unreachable.
///
/// Scoped SharedPreferences keys and on-disk directory names use the
/// **first 16 hex chars** of the toxId (`SharedPreferencesAdapter`'s
/// `_<prefix>` suffix, `AppPaths._accountPrefix`). The first 16 hex chars
/// are identical between the 64-char and 76-char representations (the
/// 76-char address is `public_key || nospam || checksum` with the public
/// key as the leading 64 chars), so prefix-keyed state does NOT need
/// re-keying. This helper deliberately does NOT touch scoped prefs or
/// directories.
///
/// Idempotent. Safe to call on every login. No-ops when the persisted ID is
/// already 76+ chars, when the FFI hasn't produced an address yet, when the
/// long ID is not a prefix-extension of the short one, or when no
/// `account_list` row matches the short ID.
class ShortToxIdBackfill {
  ShortToxIdBackfill._();

  /// Runs the backfill if [persistedToxId] is shorter than the live
  /// [service]'s resolved Tox address. Returns the canonical 76-char ID
  /// when a rewrite occurred, the unchanged persisted value when nothing
  /// needed to be done, or null when discovery failed (caller should keep
  /// using [persistedToxId] in that case).
  static Future<String?> backfillIfNeeded({
    required FfiChatService service,
    required String persistedToxId,
  }) async {
    if (persistedToxId.isEmpty) return null;
    final full = service.getSelfToxId();
    if (full == null || full.isEmpty) {
      // The FFI didn't produce an address yet (very early in login, mocked
      // test service, …). Nothing to do — a later login will pick this up.
      return persistedToxId;
    }
    if (full == persistedToxId) return persistedToxId;
    if (full.length <= persistedToxId.length) {
      // Defensive: we only rewrite "short -> long". Anything else (e.g. a
      // stored 76-char and a live 64-char fallback) is the wrong direction
      // and would lose data.
      return persistedToxId;
    }
    if (!full.startsWith(persistedToxId)) {
      // The two IDs disagree on more than just the trailing suffix. That's
      // a sign of mismatched accounts (not a truncation), so we refuse the
      // rewrite — propagating it would corrupt the wrong account record.
      AppLogger.warn(
          '[ShortToxIdBackfill] Persisted ID (${_truncate(persistedToxId)}) '
          'is not a prefix of the live address (${_truncate(full)}); '
          'skipping backfill');
      return persistedToxId;
    }

    AppLogger.log(
        '[ShortToxIdBackfill] Upgrading persisted Tox ID '
        '(${persistedToxId.length} -> ${full.length} chars) for '
        'account ${_truncate(full)}');

    // 1. Migrate password keys FIRST so a partial state (account_list moved
    //    but password keys still under the short ID) can't lock the user
    //    out. `migrateAccountPasswordKeys` is itself transactional — on
    //    failure it rolls back partial writes and returns
    //    `migrationFailed`, in which case we abort the backfill so
    //    `account_list` stays consistent with where the password lives.
    final passwordOutcome = await Prefs.migrateAccountPasswordKeys(
      fromToxId: persistedToxId,
      toToxId: full,
    );
    if (passwordOutcome == PasswordMigrationOutcome.migrationFailed) {
      AppLogger.warn(
          '[ShortToxIdBackfill] Password key migration failed; aborting '
          'backfill so account_list / pointer stay consistent with the '
          'password namespace');
      return persistedToxId;
    }

    // 2. Update the account_list entry's primary key. addAccount() with a
    //    new toxId would create a duplicate row — we need an in-place
    //    rewrite, so go through getAccountList / setAccountList directly.
    try {
      final accounts = await Prefs.getAccountList();
      final shortIdx =
          accounts.indexWhere((a) => (a['toxId'] ?? '') == persistedToxId);
      if (shortIdx >= 0) {
        final existingLongIdx =
            accounts.indexWhere((a) => (a['toxId'] ?? '') == full);
        if (existingLongIdx >= 0 && existingLongIdx != shortIdx) {
          // A 76-char row already exists alongside the 64-char row (this
          // would only happen if the user somehow has both representations
          // recorded). Drop the short copy rather than create a duplicate
          // primary key.
          AppLogger.warn(
              '[ShortToxIdBackfill] Both short and full ID rows present; '
              'dropping the short one');
          accounts.removeAt(shortIdx);
        } else {
          accounts[shortIdx]['toxId'] = full;
        }
        await Prefs.setAccountList(accounts);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[ShortToxIdBackfill] account_list rewrite failed; password keys '
          'have already moved — manual cleanup may be required',
          e,
          st);
      return persistedToxId;
    }

    // 3. Update the current-account pointer if it still points at the
    //    short form.
    try {
      final pointer = await Prefs.getCurrentAccountToxId();
      if (pointer == persistedToxId) {
        await Prefs.setCurrentAccountToxId(full);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[ShortToxIdBackfill] current-account pointer rewrite failed '
          '(account_list already updated; next login will reconcile)',
          e,
          st);
    }

    return full;
  }

  static String _truncate(String id) =>
      id.length > 16 ? '${id.substring(0, 16)}...' : id;
}
