import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import '../util/logger.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';

/// Runtime projection of the per-peer C2C receive option (mute / do-not-disturb).
///
/// Why this exists (the recvOpt propagation gap):
/// A real-UI mute flows UIKit toggle -> binary-replacement binding
/// `DartSetC2CReceiveMessageOpt` -> `V2TIMMessageManagerImpl::SetC2CReceiveMessageOpt`,
/// which stores the opt in an in-memory native map and — after the native push
/// fix — fires `OnConversationChanged` carrying the new `recvOpt`. It does NOT
/// go through `Tim2ToxSdkPlatform.setC2CReceiveMessageOpt`, so nothing persisted
/// to Prefs and nothing reached toxee's conversation cache. As a result the mute
/// never suppressed notifications and the toggle reverted on the next ~5s rebuild
/// (`_mapConv` had hardcoded `recvOpt = 0`).
///
/// This cache is toxee's synchronous projection of that native state so:
///   - `_mapConv` reads `recvOpt` synchronously when (re)building conversations,
///     with no per-row async native round-trip, and
///   - the notification path (`_shouldSuppress`) consults it directly, closing
///     the "message arrives right after mute, before the next rebuild" race.
///
/// The native map is in-memory only, so each change is persisted to Prefs (the
/// durable BACKING store) and re-hydrated per friend at session start (which also
/// re-pushes into the native map so the SDK / toggle reflect the persisted mute
/// after a restart). Prefs is persistence only — runtime reads come from here, so
/// `_mapConv` never treats Prefs as an alternate source of truth.
class C2CRecvOptCache {
  C2CRecvOptCache._();

  // key = 64-char Tox public key (normalized) -> opt (0 = receive, 2 = mute).
  static final Map<String, int> _cache = {};

  // Peers whose non-zero opt could not be re-pushed into the NATIVE map yet
  // (e.g. hydration ran before the SDK binding finished initializing). The lazy
  // hydration call sites re-attempt for these even on a cache hit — without the
  // native map entry, native C2C materialization would emit recvOpt=0 and
  // clobber the mute.
  static final Set<String> _repushPending = {};

  static String _pk(String userID) => toToxPublicKey(userID);

  /// Current opt for [userID] (0 = receive, 1 = no-notify, 2 = mute). Synchronous.
  static int optFor(String userID) {
    if (userID.isEmpty) return 0;
    return _cache[_pk(userID)] ?? 0;
  }

  /// True if [userID]'s conversation is muted (opt != 0). Synchronous.
  static bool isMuted(String userID) => optFor(userID) != 0;

  /// Update the in-memory projection only — used when applying a value that is
  /// already authoritative (the native `OnConversationChanged` push, or a value
  /// just read back from Prefs during hydration).
  static void setLocal(String userID, int opt) {
    if (userID.isEmpty) return;
    _cache[_pk(userID)] = opt;
  }

  /// Update the projection AND persist to Prefs (durable backing store). Used
  /// when toxee observes a recvOpt change from the native push and wants it to
  /// survive a restart. [selfToxId] scopes the Prefs key to the current account.
  static Future<void> setAndPersist(
      String userID, int opt, String? selfToxId) async {
    if (userID.isEmpty) return;
    _cache[_pk(userID)] = opt;
    await Prefs.setC2CReceiveMessageOpt(userID, opt, selfToxId);
  }

  /// True if the projection already has an entry for [userID] (hydrated or
  /// pushed). Used by the live conversation event path to lazily hydrate peers
  /// whose conversations appear only after the provider seed.
  static bool contains(String userID) =>
      userID.isNotEmpty && _cache.containsKey(_pk(userID));

  /// True if [userID] still needs a hydration pass: either the projection has
  /// no entry yet, or a previous non-zero opt failed its native-map re-push
  /// (SDK not initialized at the time) and must be retried so native C2C
  /// materialization stops emitting a stale 0.
  static bool needsHydration(String userID) {
    if (userID.isEmpty) return false;
    final pk = _pk(userID);
    return !_cache.containsKey(pk) || _repushPending.contains(pk);
  }

  /// Hydrate one peer's opt from Prefs into the projection, AND re-push a
  /// non-zero opt back into the NATIVE receive-opt map. The re-push is
  /// required for correctness, not cosmetics: native C2C conversation
  /// materialization reads ONLY the in-memory native map (the single source of
  /// truth at emit time), so after a process restart an un-hydrated native map
  /// would make the first native C2C emit carry recvOpt=0 — which the
  /// onConversationChanged handler would treat as an authoritative un-mute and
  /// persist, silently clearing the user's mute. Re-pushing via the SDK's
  /// setC2CReceiveMessageOpt repopulates the map (and idempotently re-confirms
  /// this cache through the native push). Best-effort: the SDK may not be fully
  /// initialized at the earliest hydration site; the lazy per-conversation
  /// hydration paths retry later. Returns the opt.
  static Future<int> hydrateFromPrefs(String userID, String? selfToxId) async {
    if (userID.isEmpty) return 0;
    final opt = await Prefs.getC2CReceiveMessageOpt(userID, selfToxId);
    final pk = _pk(userID);
    _cache[pk] = opt;
    if (opt != 0 && opt < ReceiveMsgOptEnum.values.length) {
      unawaited(() async {
        try {
          final r = await TencentImSDKPlugin.v2TIMManager
              .getMessageManager()
              .setC2CReceiveMessageOpt(
                userIDList: [pk],
                opt: ReceiveMsgOptEnum.values[opt],
              );
          if (r.code == 0) {
            _repushPending.remove(pk);
          } else {
            _repushPending.add(pk);
          }
        } catch (e) {
          _repushPending.add(pk);
          AppLogger.debug(
              '[C2CRecvOptCache] native re-push failed (will retry lazily): $e');
        }
      }());
    } else {
      _repushPending.remove(pk);
    }
    return opt;
  }

  @visibleForTesting
  static void debugClear() => _cache.clear();

  @visibleForTesting
  static Map<String, int> debugSnapshot() => Map.unmodifiable(_cache);
}
