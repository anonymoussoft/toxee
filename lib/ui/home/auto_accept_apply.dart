import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../util/prefs.dart';

/// Load the account-scoped "auto-accept group invites" preference for [toxId]
/// and apply it at HomePage bootstrap (S47, the Dart half): mirror it into the
/// UI via [mirrorToUi] and push it into the native auto-accept gate via
/// [FfiChatService.setAutoAcceptGroupInvites] — both ONLY while [isStillMounted].
///
/// The order is deliberate and byte-for-byte matches the original inline
/// bootstrap (`if (mounted) { setState(mirror); service.set(value); }`):
/// [mirrorToUi] runs BEFORE the native push, so even if the synchronous FFI
/// setter throws, the UI still reflects the persisted value (codex). The
/// [isStillMounted] gate preserves the other half — an account switch that
/// unmounts HomePage before the async `Prefs.get` resolves must NOT mirror or
/// push a stale value into a service that may already be re-initialising for
/// another account.
///
/// Returns the loaded value. Extracted from the HomePage bootstrap so this
/// Pref→(UI + native-gate) apply is L1-testable without pumping HomePage.
Future<bool> loadAndApplyAutoAcceptGroupInvites(
  FfiChatService service,
  String toxId, {
  required bool Function() isStillMounted,
  required void Function(bool value) mirrorToUi,
}) async {
  final value = await Prefs.getAutoAcceptGroupInvites(toxId);
  if (isStillMounted()) {
    mirrorToUi(value);
    service.setAutoAcceptGroupInvites(value);
  }
  return value;
}
