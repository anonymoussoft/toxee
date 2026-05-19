/// Shared key-scoping helper for account-scoped SharedPreferences storage.
///
/// Historically two parallel implementations of this same `${key}_${prefix}`
/// pattern existed:
///
///   * `Prefs._scopedKey` in `lib/util/prefs.dart`
///   * `SharedPreferencesAdapter._prefixKey` in `lib/adapters/shared_prefs_adapter.dart`
///
/// They could drift silently — fixing a bug in one didn't fix the other.
/// X2 from `docs/designs/local-storage-review-2026-05-18.md` calls for a
/// single shared helper. Both call sites now delegate here.
///
/// Contract:
///   * [accountPrefix] is passed through verbatim (callers are responsible
///     for any truncation, e.g. `Prefs` truncates the toxId to 16 chars
///     before calling).
///   * When [accountPrefix] is null or empty, [rawKey] is returned unchanged
///     (no scope applied — used for global keys and legacy/unscoped fallback).
///   * Otherwise, returns `'${rawKey}_${accountPrefix}'` — the format that
///     both legacy call sites produced, kept byte-identical so existing
///     on-disk SharedPreferences entries continue to be found.
String scopedPrefsKey(String rawKey, String? accountPrefix) {
  if (accountPrefix == null || accountPrefix.isEmpty) return rawKey;
  return '${rawKey}_$accountPrefix';
}
