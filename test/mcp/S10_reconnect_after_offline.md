# S10 — Reconnect after going offline (no messages)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online→offline→online sessionPwd=none profileCrypt=plaintext`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because requires real `ifconfig <iface> down/up` (root) and live Tox DHT recovery
**Status**: covered. The full offline→online round-trip (sidebar dot/label flip driven by the real DHT) stays an L3 playbook. The **UI half** — the connection-status banner reacting to the production `isConnected` stream (`FfiChatService.connectionStatusStream`), plus the send-error banner — is now covered at the widget layer (L1).
**Covered-by** (UI half): `test/ui/home/home_banners_real_ui_test.dart` (widget-layer L1: drives the real `ConnectionStatusBanner` via its production `Stream<bool>` status source — offline tick shows the banner, reconnect collapses it, banner tap invokes the production `onRetry`; also covers the `ErrorBanner` send-error surface and its retry/dismiss handlers).

Connection-state-only baseline. Sister scenario `S25_offline_queue.md` is the messages-queued variant; S25 depends on S10 passing.

## Precondition
- Fixture A: account A signed in, profile plaintext, sidebar `<nicknameA>\nOnline`
- Sudo pre-warmed (`sudo -v` + keepalive loop), or passwordless sudoers rule for `ifconfig <iface> down/up`
- Network interface known (default `en0`; substitute as needed); only one routable interface (or down them all)
- Locale pinned to `en` so sidebar literal `Online` / `Offline` is stable
- `MCP_BINDING=marionette`
- Tear-down trap: restore `sudo ifconfig <iface> up` on script exit

## Driver
1. Snapshot, poll up to 60s for sidebar `_UserAvatar` label `<nicknameA>\nOnline`; capture `official.get_runtime_errors({})` baseline
2. Shell: `sudo ifconfig $IFACE down`
3. Poll log up to 15s for `HandleSelfConnectionStatus: Notified self offline status (userID=<toxIdA>`; poll snapshot up to 15s for sidebar label flip to `<nicknameA>\nOffline`
4. Hold offline 5–15s (stay under 30s to avoid the `_noConnectionBannerTimer` SnackBar); re-snapshot — assert still Offline; no second `Notified self online status` in this window
5. Shell: `sudo ifconfig $IFACE up`
6. Poll log up to 120s for `HandleSelfConnectionStatus: Notified self online status (userID=<toxIdA>`; poll snapshot up to 15s for sidebar back to `\nOnline`
7. Verify `official.get_runtime_errors({})` matches baseline; grep negative markers below

## Assertions
- A2: log contains `Notified self offline status (userID=<toxIdA>` after Step 2 (gated by line range — only after Step 1's snapshot)
- A3: sidebar `_UserAvatar` flips to `<nicknameA>\nOffline` (snapshot label) — status dot color flips from `successColor` to muted secondary
- A4 (steady-state): during the 5–15s hold, no spurious `Notified self online status` line; sidebar still Offline
- A5: log contains `Notified self online status (userID=<toxIdA>` after Step 5
- A6: sidebar back to `<nicknameA>\nOnline`; dot back to `successColor`
- A7: log contains exactly **one** `[FfiChatService] ========== startPolling called ==========` (from initial login) and zero subsequent `[FfiChatService] init` lines
- A8: `official.get_runtime_errors({})` equals Step-1 baseline
- A9 (negative): no `FATAL`, `bad_alloc`, `terminate called`, `tox_kill`, `_connectionStatus.close()` in log

## Notes
- `ConnectionStatusBanner` widget exists at `lib/ui/widgets/connection_status_banner.dart:20` but is **not auto-mounted** — S10 does NOT assert on a persistent banner; only sidebar dot + label.
- Step 4 polls log first (UI is downstream of `_connectionStatus.add(false)` at `ffi_chat_service.dart:1499/4050`).
- Step 6 DHT re-bootstrap is the wall-clock variance (5–120s); cold cache → long end.
- macOS may need pre-approved keychain ACL (`flutter_secure_storage`) to avoid blocking dialog on first launch.
