/// App-scoped feature flags.
///
/// Flags are intentionally `const bool` so the Dart compiler can tree-shake
/// the disabled branches at build time. Toggling a flag requires a code change
/// + rebuild, not a runtime config — this is by design for the identity
/// portability rollout (per the CEO plan, item "Phased delivery"):
///
/// > Feature flags live in a new `lib/util/feature_flags.dart` —
/// > app-scoped, NOT in `prefs_interfaces.dart` which is the Tim2Tox bridge
/// > boundary.
///
/// Add new flags here in **alphabetical order** so concurrent PRs don't
/// collide on the same neighbour lines.
class FeatureFlags {
  FeatureFlags._();

  /// First-run backup wizard + restore-on-new-device flow polish (PR 1).
  ///
  /// Default per CEO plan: **TRUE on merge** (UI change, low risk; flip false
  /// if a user-reported issue appears).
  static const bool enableFirstRunBackupWizard = true;

  /// QR + LAN cross-device pairing (PR 2).
  ///
  /// Default per CEO plan: **FALSE on merge, FLIP TRUE after one release of
  /// canary + manual smoke on three platforms.** UI affordance hidden when
  /// off.
  ///
  /// Scope reminder: this is a *convenience* feature for the both-devices-in-
  /// the-same-room case, NOT a device-loss recovery path. Device loss is
  /// covered solely by `.tox` export + restore (`enableFirstRunBackupWizard`).
  static const bool enableQRPairing = false;
}
