import 'package:tim2tox_dart/service/ffi_chat_service.dart';

/// toxee-side extension on [FfiChatService] that returns a value safe to use
/// as the primary key for account-scoped persistence (SharedPreferences,
/// secure storage, file paths, account_list records).
///
/// Why this matters: `FfiChatService.selfId` returns the V2TIM login
/// `userId` string passed to `login(userId, userSig)`. toxee always passes
/// the placeholder `'FlutterUIKitClient'` there because Tox has no V2TIM
/// userId / userSig concept. So `selfId` does NOT identify the Tox
/// account — every site that used `service.selfId` for `Prefs.addAccount`,
/// `Prefs.setAccountPassword`, `Prefs.setAutoAcceptFriends`, the personal
/// QR card display, file-path derivation, etc. was silently keying
/// everything under the placeholder string. The result was an entire class
/// of bugs where the visible "User ID" was `FlutterUIKitClient`, account
/// records collided across users, and per-account settings vanished after
/// any rename-style operation.
///
/// [getSelfToxId] returns the 76-hex-char Tox address (public key +
/// nospam + checksum) — the real identity. [accountKey] is the canonical
/// resolver: prefer the real Tox address, fall back to [selfId] only when
/// the FFI hasn't produced one yet (very early startup, test mocks).
/// Sites that compare against V2TIM message-level `userID` fields (the
/// sender id on `OnRecvMsg`, the routing key on UIKit's data layer, log
/// strings, plugin user_id params) should continue to use [selfId] — those
/// genuinely want the V2TIM string. Anything keying durable storage,
/// hashing passwords, deriving paths, or showing the Tox ID to the user
/// should use [accountKey].
extension FfiChatServiceAccountKey on FfiChatService {
  /// Returns the 76-char Tox address when login has resolved it; falls back
  /// to [selfId] (the V2TIM login placeholder) otherwise. Never returns
  /// null — the fallback ensures any guard like `if (accountKey.isEmpty)`
  /// behaves the same as the previous `selfId.isEmpty` check used across
  /// the codebase.
  ///
  /// **Read/display only.** Do NOT use this for *first-time* persistence
  /// of an account identity — the placeholder fallback would silently
  /// re-create the original `FlutterUIKitClient`-keyed corruption.
  /// `AccountService.registerAccount` and similar code paths that ESTABLISH
  /// the toxId-keyed namespace should call [getSelfToxId] directly and
  /// throw / abort when it returns null instead of accepting the
  /// placeholder. Reads of *already-persisted* accounts (Settings actions,
  /// QR display, snackbar copy, auto-accept toggles) are fine — a stale
  /// placeholder there will miss the (already-correctly-keyed) record and
  /// no-op rather than corrupt anything.
  String get accountKey {
    final real = getSelfToxId();
    if (real != null && real.isNotEmpty) return real;
    return selfId;
  }
}
