# S59 — Notification permission revoke / regrant

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate macOS Containers) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1 history=seeded window=default`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — two coupled OS gates: the `com.toxee.app` UNUserNotification authorization (TCC-owned, not a Prefs axis) AND a live inbound message, which has no source seam to inject. Sibling of S58 (badge + notification lifecycle), which shares the macOS Notification Center observability.
**Status**: OS-gated — macOS notification authorization (TCC) is decided once by the OS at NotificationService.init() and cannot be granted/denied programmatically in a headless run; the grant is the irreducible OS gate. The in-app request fires at init. (Notification-tap routing and mute-suppression behavior are covered by S53/S83.)

## Precondition
- Two toxee instances in separate macOS Containers with distinct `CFBundleIdentifier` — A is `com.toxee.app` (the app under test; `macos/Runner/Info.plist:11` → `PRODUCT_BUNDLE_IDENTIFIER`), B is a different bundle e.g. `com.toxee.b.app` so `SharedPreferences`/TCC entries don't clobber.
- A and B already friends (`friends=1`); one C2C conversation between them with seeded history.
- A: app in foreground but the A↔B conversation NOT the active/open one (otherwise `_shouldSuppress` returns true on the foreground+active-conv guard, `notification_message_listener.dart:207-211`).
- A: conversation is NOT muted — `recvOpt == 0` in UIKit's conversation cache (`notification_message_listener.dart:219-229`); if muted the banner is suppressed regardless of OS permission.
- macOS Notification authorization for `com.toxee.app` = Granted at session start (`NotificationService.init` calls `MacOSFlutterLocalNotificationsPlugin.requestPermissions(alert/badge/sound)`, `notification_service.dart:227-237`).
- Accessibility permission for the controlling terminal — `osascript -e 'tell application "System Events" to count processes'` succeeds.

## Driver
1. Snapshot A — confirm the A↔B conversation row exists and is not the open chat; capture `official.get_runtime_errors({})` baseline on both.
2. REVOKE: `tccutil reset Notifications com.toxee.app` (clears the authorization for A's bundle; takes effect for newly-posted banners — no relaunch needed for the suppression assertion, but the `_initialized` permission was cached at launch — see Notes).
3. On B: send one text message to A (drives the add-friend-established C2C channel).
4. Wait ~2s (poll cycle + `BadgeService` 200 ms debounce, `badge_service.dart:46`).
5. Assert NO OS banner posted for A, but in-app unread/badge DID update (assertions below).
6. REGRANT: re-enable notifications for `com.toxee.app` — either System Settings → Notifications → Toxee → Allow, or relaunch A after the TCC reset so `MacOSFlutterLocalNotificationsPlugin.requestPermissions` re-prompts and the system dialog is accepted (Accessibility-driven click or one-time manual approval).
7. On B: send a second text message to A.
8. Wait ~2s.
9. Assert the second inbound DOES post an OS banner.

## Assertions
- Step 1: both sessions `get_runtime_errors` empty.
- Step 3/4 (suppressed): A's log contains `[BadgeService] badge written: <N+1>` (in-app unread still advances — the badge path is independent of OS notification authorization).
- Step 5 (negative): NO macOS banner for `com.toxee.app` — assert via `log stream --predicate 'subsystem == "com.apple.UserNotifications.UNUserNotificationCenter"'` showing no `Banner` deliver for the bundle, OR AppleScript scrape of Notification Center returns no new Toxee entry. Note: `NotificationMessageListener._onRecvNewMessage` still RUNS and calls `showMessageNotification` — there is no log line confirming the banner was *posted* vs *dropped by OS* (see Notes); absence of a TCC-authorized delivery in `log stream` is the only signal.
- Step 5: A's log does NOT contain `[NotificationService] showMessageNotification failed for conv=` (the macOS plugin swallows a denied authorization silently rather than throwing — `notification_service.dart:385-392`).
- Step 7/8 (regranted): A's log contains a second `[BadgeService] badge written: <N+2>` AND `log stream` shows a UNUserNotificationCenter banner deliver for `com.toxee.app`.
- Step 9: AppleScript / Notification Center now contains a Toxee banner titled with B's resolved sender name (friendRemark → nickName → trimmed toxId, `notification_message_listener.dart:239-255`); body is B's message text clamped to 80 chars (`_maxBodyChars`, `notification_service.dart:63`).
- Bidirectional sanity: B's `get_runtime_errors` empty after both sends.

## Notes
- macOS permission is OS/TCC-owned for the `com.toxee.app` container — it is NOT a Prefs axis and has no per-account scoped key. (`_androidPermissionGranted` caching in `notification_service.dart:79` is Android-only and never consulted on macOS.)
- `NotificationService._initialized` and the macOS authorization are decided once at `init()`; a mid-session `tccutil reset` may not flip already-granted runtime state until relaunch — prefer relaunch-after-reset for a clean revoke, and treat Step 2's no-relaunch path as best-effort.
- Observability gap: there is no `[NotificationService] posted banner` log line (S58 referenced one that does not exist). The only proof a banner reached the OS is `log stream` on the UNUserNotificationCenter subsystem; verify with that, not a Toxee log marker.
- Blocked on Fixture C: the inbound trigger requires a live twin (B) over the DHT. There is NO FFI test-inject shim (`grep lib/ third_party/tim2tox/dart/lib` for `testInject*` returns nothing as of 2026-05-29), so the banner cannot be driven from a single instance. Until `doc/research/MULTI_INSTANCE_SPIKE.en.md` passes this stays backlog.
- "+ OS permission gate" on the Status line: beyond the Fixture C inbound trigger, this scenario is also gated by the `com.toxee.app` UNUserNotification authorization, which is TCC-owned (not a Prefs axis) and decided once at `init()` — so a clean revoke/regrant needs relaunch (see the `_initialized` note above). Both gates must be satisfied for the banner assertions to be drivable.
- macOS-only scenario.
