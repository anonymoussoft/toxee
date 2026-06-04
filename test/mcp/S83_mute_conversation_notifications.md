# S83 — Mute a conversation → inbound message notification suppressed

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate macOS Containers) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1 history=seeded window=default`
**Harness mode**: peerHarness=none (real twin B required — echo peer is not Fixture C)
**Promotion target**: L3-pinned — needs (a) a live inbound message from a twin over the DHT (no FFI inject seam) and (b) OS-notification suppression verified via `log stream`; neither is observable at L1/L2.
**Status**: mute-state half covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_mute.sh` (`l3_set_c2c_recv_opt` sets `recvOpt=2` in Prefs AND in the UIKit conversation cache entry `_shouldSuppress` reads; asserts `l3_dump_state.conversations[].recvOpt==2` — `recvOpt != 0` is exactly the suppression input). Validated live 2026-06-01. The OS-banner-absence proof (`log stream` on UNUserNotificationCenter) remains OS-gated and out of scope for this gate.

## Precondition
- A and B already friends (`friends=1`); one C2C conversation A↔B with seeded history.
- A: app foreground but the A↔B conversation NOT the open/active chat (else the foreground+active-conv guard suppresses regardless, `notification_message_listener.dart:207-211`).
- A: macOS Notification authorization for `com.toxee.app` = Granted at session start (so a non-muted inbound WOULD post a banner — the control half).
- AppleScript/Accessibility for the controlling terminal (`osascript -e 'tell application "System Events" to count processes'` succeeds).
- Locale pinned `en`.

## Driver
1. Connect to A; `fmt_semantic_snapshot` → confirm the A↔B row exists and is not the open chat; capture `official.get_runtime_errors({})` baseline on both.
2. CONTROL (unmuted): on B, send text msg #1 to A; wait ~2s → assert a banner IS posted (A4) — confirms the path is live before muting.
3. MUTE: open A's contact/user profile for B; toggle `UiKeys.userProfileConversationMuteSwitch` (`user_profile_conversation_mute_switch`) on → `_setC2CReceiveOpt(true)` calls `setC2CReceiveMessageOpt(opt=V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE)` (`tencent_cloud_chat_user_profile_body.dart:488-494`), persisted verbatim as `recvOpt=2` (`V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE=2`, `V2TIMCommon.h:47`; adapter `setInt(key, opt)`, `shared_prefs_adapter.dart:522-530`) and pushed into the UIKit conversation cache (`conversationList[i].recvOpt`).
4. On B, send text msg #2 to A; wait ~2s (poll cycle + `BadgeService` 200ms debounce, `badge_service.dart:112`).
5. Assert NO OS banner for msg #2, but unread/badge DID advance (Assertions).

## Assertions
- A1: both sessions `get_runtime_errors` empty at Step 1.
- A2 (mute applied): A's UIKit `conversationList` entry for `c2c_<pubkeyB>` has `recvOpt != 0` after Step 3 — this is exactly what `_shouldSuppress` reads at `notification_message_listener.dart:224-225` (`if (recvOpt != null && recvOpt != 0) return true;`). Verify via `official.get_widget_tree` / Prefs key (`_c2cRecvOptKey`).
- A3 (suppressed): after Step 4, A's log contains `[BadgeService] badge written: <N+1>` (`badge_service.dart:112`) — unread/badge path is independent of the mute guard.
- A4 (control, Step 2): `log stream --predicate 'subsystem == "com.apple.UserNotifications.UNUserNotificationCenter"'` shows a banner deliver for `com.toxee.app` (titled with B's resolved name — friendRemark→nickName→trimmed toxId, `notification_message_listener.dart:239-255`).
- A5 (suppressed, Step 4): the same `log stream` shows NO new UNUserNotificationCenter banner deliver for `com.toxee.app` after msg #2. `_onRecvNewMessage` early-returns at `notification_message_listener.dart:156` (`if (_shouldSuppress(message)) return;`) so `showMessageNotification` is never called — there is no Dart log marker for the suppression (behavioral), and no `[NotificationService] showMessageNotification failed` line either.
- A6 (negative): no `FATAL`/`terminate called`; both sessions `get_runtime_errors` match baseline.

## Notes
- Mute UI affordance is the per-contact Do-Not-Disturb switch in the UIKit user-profile body (`_setC2CReceiveOpt`, `tencent_cloud_chat_user_profile_body.dart:488`); it now exposes `user_profile_conversation_mute_switch`. It WRITES `V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE` = `recvOpt=2`, and its on-state display reads `recvOpt == 2` (line 469). `_shouldSuppress` suppresses on `recvOpt != 0` (`notification_message_listener.dart:225`), so 2 → suppressed — verified.
- Suppression proof is `log stream` absence (sibling S59/S58 method) — there is no `[NotificationService] posted banner` log line in the codebase.
- Blocked on Fixture C: the inbound trigger needs a live twin (B) over the DHT; no `testInject*` FFI shim exists in `lib/` or tim2tox, so the message cannot be driven from one instance. Until `doc/research/MULTI_INSTANCE_SPIKE.en.md` lands this stays backlog.
- Secondary gate (OS notification + log-stream): even once Fixture C lands, the control assertion (A4) requires `com.toxee.app` notification authorization Granted — TCC-owned, decided once at `NotificationService.init()`; grant ahead via `tccutil`/one-time approval. Suppression is proved by `log stream` predicate absence (A4/A5), so the run also needs `log stream` access on the controlling host. macOS-only. (This is the gate previously folded into the Status string.)
