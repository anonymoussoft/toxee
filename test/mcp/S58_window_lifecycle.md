# S58 — Window minimize / restore lifecycle (badge + notification)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online friends=1 history=N-unread window=visible`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — needs real OS lifecycle events (`AXMinimized`), real dock badge, and real macOS Notification Center; cannot be hermeticized.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_window.sh` (A minimizes via l3_window_state, twin B sends a message, A still receives it over the DHT while backgrounded, then A restores). Validated live 2026-06-01.

## Precondition
- Account A signed in, online; one C2C conversation with `N>=1` unread (pre-staged by Fixture C twin sending N messages before launch).
- macOS Notification permission for `com.toxee.app` = Granted.
- AppleScript / Accessibility permission for the controlling terminal — verify with `osascript -e 'tell application "System Events" to count processes'`.
- No other Toxee window currently minimized.
- Dock badge value matches N before scenario begins.

## Driver
1. Snapshot sidebar — confirm conversation row shows numeric badge `N`; `AXMinimized==false`; dock-badge ≈ N.
2. Minimize: `osascript -e 'tell application "System Events" to set value of attribute "AXMinimized" of window 1 of process "Toxee" to true'`.
3. Wait 500 ms; verify `AXMinimized==true`; dock badge still N.
4. Deliver one inbound message from a Fixture C twin (the only path — no debug inject shim exists; `testInject*` is absent from the codebase).
5. Within ~1s: assert dock badge = N+1; assert OS notification posted (via `log stream`, see Notes).
6. Restore: `osascript -e 'tell application "Toxee" to activate'`; wait 500 ms.
7. (Optional 7b) Tap the unread conversation row → unread cleared → badge → 0.

## Assertions
- Step 2: there is NO pause-side log today — `didChangeAppLifecycleState` only branches on `resumed` (`main.dart:243-253`). Verify the minimize behaviorally via `AXMinimized==true` (Driver step 3) and no new `[BadgeService] badge written:` line. (A `[main] lifecycle paused` marker would need an observability add — see Notes.)
- Step 3: no new `[BadgeService] badge written:` line (debounced writer dedups identical totals).
- Step 5: log contains `[BadgeService] badge written: N+1` (`badge_service.dart:112`, `AppLogger.debug`). There is NO Dart success log for the banner post (`NotificationService._plugin.show`, `notification_service.dart:373`) and no `[FakeIM] unread total` log — assert the banner via `log stream` (Notes) and assert the failure path `[NotificationService] showMessageNotification failed for conv=<id>` (`notification_service.dart:390`) is ABSENT.
- Step 5: dock-badge AXStatusLabel for "Toxee" reads `N+1`; window stays minimized (OS notif did not auto-restore).
- Step 6: on resume the app calls `FakeUIKit.instance.im?.refreshUnreadTotal()` (`main.dart:246`) with no success log; assert the failure log `[EchoUIKitApp] refreshUnreadTotal on resume failed` (`main.dart:249`) is ABSENT. (No `[main] lifecycle resumed` marker exists today — observability add, see Notes.)
- Step 7a (no open): dock badge stays N+1; conversation row still shows N+1 badge in snapshot.
- Step 7b (open): log shows `[BadgeService] badge written: 0`; dock badge clears; row badge gone.
- Negative: banner was NOT suppressed — `NotificationMessageListener._shouldSuppress` (`notification_message_listener.dart:182`) returns false here because the window is paused (`isFocused==false`, so the active-conversation guard can't apply) and the contact isn't muted. This is behavioral (the method emits no log line); confirm via the banner appearing in `log stream` + the failure-warn absent.

## Notes
- Pause/resume lifecycle markers are NOT logged today — the only lifecycle log is the resume-failure at `main.dart:249`. Asserting "lifecycle paused/resumed" from logs would need observability adds. Until then, lean on `AXMinimized` state + `[BadgeService] badge written` for hard assertions.
- `BadgeService` debounces 200 ms — wait ≥300 ms after inbound before asserting `badge written`.
- Dock badge cannot be read via `defaults`; either use the `[BadgeService] badge written` log line (preferred) or `AXStatusLabel` of dock UI element with Accessibility permission.
- Notification Center scrape is brittle; prefer log assertion plus `log stream --predicate 'subsystem == "com.apple.UserNotifications.UNUserNotificationCenter"'`.
- Without a Fixture C twin, only the lifecycle markers can be tested (no inbound to verify badge bump) — there is no FFI inject shim to substitute, hence `Status: blocked on Fixture C spike`.
- `FfiChatService.startPolling()` is NOT lifecycle-gated on desktop — poll thread keeps running while window is minimized.
